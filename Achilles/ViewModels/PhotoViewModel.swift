// MARK: - PhotoViewModel Summary

// This ViewModel manages the display and interaction with photos and videos from the user's Photo Library.
// It handles authorization, phased scanning of years with media, loading content for specific years (featured and grid views),
// pre-fetching of adjacent year content (thumbnails and featured images), image and Live Photo caching,
// cancellation and retrying of loading tasks, and cleanup. It publishes UI-related state such as
// page loading states, available years, authorization status, and animation completion flags.
// It utilizes a PhotoLibraryService for interacting with Photos framework, a FeaturedSelectorService
// to pick featured items, an ImageCacheService for in-memory caching, and a MediaItemFactory to create
// MediaItem objects from PHAssets. It also includes functionality for reverse geocoding asset locations.

import SwiftUI
import Photos
import AVKit
import UIKit
import Combine // Needed for Combine framework elements if used elsewhere

@MainActor // Ensure UI updates happen on the main thread
class PhotoViewModel: ObservableObject {

    // MARK: - Nested Constants
    private struct Constants {
        // Configuration
        static let maxYearsToScanTotal: Int = 20        // Total years to eventually scan
        static let initialScanPhaseYears: Int = 4         // Years to scan in the first phase
        static let yearCheckFetchLimit: Int = 1           // Fetch limit when checking if year has content
        static let initialFetchLimitForLoadPage: Int = 10 // Fetch first 10 to find featured quickly
        static let maxPhotosToDisplay: Int = 20
        static let samplingPoolLimit: Int = 300
        // Image Sizes
        static let defaultThumbnailSize = CGSize(width: 200, height: 200)
        static let prefetchThumbnailSize = CGSize(width: 200, height: 200) // Use this for proactive thumbnail loading

        // Date Calculationsc
        static let daysToAddForDateRangeEnd: Int = 1

        // Other Logic
        static let fullProgress: Double = 1.0
    }

    // MARK: - Dependencies
    private let service: PhotoLibraryServiceProtocol // Keep if used elsewhere
    private let imageManager = PHCachingImageManager()
    private let imageCacheService: ImageCacheServiceProtocol
    private let factory: MediaItemFactoryProtocol
    
    let selector: FeaturedSelectorServiceProtocol

    // MARK: - Published Properties for UI
    @Published var pageStateByYear: [Int: PageState] = [:]
    @Published var availableYearsAgo: [Int] = []
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var initialYearScanComplete: Bool = false // Now means Phase 1 is complete
    // MARK: - Internal Properties
    // Task Management
    private var activeLoadTasks: [Int: Task<Void, Never>] = [:]
    private var activePrefetchThumbnailTasks: [Int: Task<Void, Never>] = [:]
    private var activeFeaturedPrefetchTasks: [Int: Task<Void, Never>] = [:]
    private var backgroundYearScanTask: Task<Void, Never>? = nil // Task for Phase 2 scan
    private var memoryWarningObserver: NSObjectProtocol?
    private var cachedAssetsByYear: [Int: [PHAsset]] = [:] // IMPROVEMENT 2: Track assets cached via startCachingImages

    
    // Preloaded Data Storage
    private var preloadedFeaturedImages: [Int: UIImage] = [:]

    var thumbnailSize = Constants.defaultThumbnailSize

    // IMPROVEMENT 4: Screen-resolution target size for detail view.
    // Computed on the class (which is @MainActor) to guarantee UIScreen.main access is on the main thread.
    private lazy var displayImageSize: CGSize = {
        let screen = UIScreen.main
        return CGSize(width: screen.bounds.width * screen.scale,
                      height: screen.bounds.height * screen.scale)
    }()

    // Caching Properties
    private var activeRequests: [String: PHImageRequestID] = [:]

    // MARK: - Initialization
    init(
        service: PhotoLibraryServiceProtocol = PhotoLibraryService(),
        selector: FeaturedSelectorServiceProtocol = FeaturedSelectorService(),
        imageCacheService: ImageCacheServiceProtocol = ImageCacheService(),
        factory: MediaItemFactoryProtocol = MediaItemFactory()
    ){
        self.service = service
        self.selector = selector
        self.imageCacheService = imageCacheService
        self.factory = factory
        checkAuthorization()
        
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            debugLog("PhotoViewModel: Memory warning received")
            Task { @MainActor in
                self?.clearImageCache()
            }
        }
    }

    // MARK: - Authorization Handling
    func checkAuthorization() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        handleAuthorization(status: status)
    }

    private func handleAuthorization(status: PHAuthorizationStatus) {
         self.authorizationStatus = status
         switch status {
         case .authorized, .limited:
             debugLog("Photo Library access status: \(status)")
             if !initialYearScanComplete && backgroundYearScanTask == nil {
                  Task { await startYearScanningProcess() }
             }
             Task.detached(priority: .background) {
                 await PhotoIndexService.shared.buildIndex()
                 await PhotoIndexService.shared.rebuildIfNeeded()
             }
         case .restricted, .denied:
             debugLog("Photo Library access restricted or denied.")
             self.pageStateByYear = [:]
             self.availableYearsAgo = []
             self.initialYearScanComplete = true
             backgroundYearScanTask?.cancel(); backgroundYearScanTask = nil
         case .notDetermined:
             debugLog("Requesting Photo Library access...")
             requestAuthorization()
         @unknown default:
             debugLog("Unknown Photo Library authorization status.")
             self.initialYearScanComplete = true
             backgroundYearScanTask?.cancel(); backgroundYearScanTask = nil
         }
     }

    private func requestAuthorization() {
        Task {
            let requestedStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            await MainActor.run {
                self.handleAuthorization(status: requestedStatus)
            }
        }
    }

    // MARK: - Content Loading & Prefetching

    private func startYearScanningProcess() async {
        guard !initialYearScanComplete else {
            debugLog("Initial year scan (Phase 1) already complete.")
            return
        }
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            debugLog("Cannot scan for years without photo library access.")
            await MainActor.run { self.initialYearScanComplete = true }
            return
        }
        backgroundYearScanTask?.cancel()
        backgroundYearScanTask = nil

        // MARK: Phase 1 (foreground)
        let initialRange = 1...Constants.initialScanPhaseYears
        debugLog("Starting Phase 1 scan for years: \(initialRange)")

        var phase1Error: Error? = nil
        var initialYearsFound: [Int] = []

        do {
            initialYearsFound = try await scanYearsInRange(range: initialRange)
            debugLog("Phase 1 scan complete. Found years: \(initialYearsFound.sorted())")
        } catch is CancellationError {
            debugLog("Phase 1 scan cancelled.")
            return
        } catch {
            debugLog("Error during Phase 1 scan: \(error.localizedDescription)")
            phase1Error = error
        }

        await MainActor.run {
            self.availableYearsAgo = initialYearsFound.sorted()
            self.initialYearScanComplete = true
            if let error = phase1Error {
                debugLog("Phase 1 completed with error: \(error.localizedDescription)")
            }
        }

        // MARK: Phase 2 (background)
        let remainingRange = (Constants.initialScanPhaseYears + 1)...Constants.maxYearsToScanTotal
        guard !remainingRange.isEmpty else {
            debugLog("No remaining years to scan in Phase 2.")
            return
        }

        debugLog("Starting Phase 2 background scan for years: \(remainingRange)")

        backgroundYearScanTask = Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }

            do {
                let foundYears = try await self.scanYearsInRange(range: remainingRange)
                try Task.checkCancellation()
                debugLog("Phase 2 scan complete. Found additional years: \(foundYears.sorted())")

                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    let combined = Set(self.availableYearsAgo + foundYears)
                    self.availableYearsAgo = Array(combined).sorted()
                    debugLog("Combined available years: \(self.availableYearsAgo)")
                }
            } catch is CancellationError {
                debugLog("Phase 2 scan task cancelled.")
            } catch {
                debugLog("Error during Phase 2 background scan: \(error.localizedDescription)")
            }

            await MainActor.run { self.backgroundYearScanTask = nil }
        }
    }

    private func scanYearsInRange(range: ClosedRange<Int>) async throws -> [Int] {
        var foundYears: [Int] = []
        let calendar = Calendar.current
        let today = Date()
        debugLog("Scanning range: \(range)...")
        for yearsAgoValue in range {
            try Task.checkCancellation()
            guard let targetDateRange = calculateDateRange(yearsAgo: yearsAgoValue, calendar: calendar, today: today) else {
                debugLog("Skipping year \(yearsAgoValue) due to date calculation error.")
                continue
            }
            let fetchOptions = PHFetchOptions()
            let predicates = [
                NSPredicate(format: "creationDate >= %@ AND creationDate < %@", targetDateRange.start as NSDate, targetDateRange.end as NSDate),
                NSPredicate(format: "isHidden == NO")
            ]
            fetchOptions.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            fetchOptions.fetchLimit = Constants.yearCheckFetchLimit
            let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
            if fetchResult.firstObject != nil {
                 foundYears.append(yearsAgoValue)
            }
        }
        debugLog("Finished scanning range: \(range). Found: \(foundYears.count > 0 ? foundYears.sorted() : [])")
        return foundYears
    }

    func loadPage(yearsAgo: Int) {
        guard activeLoadTasks[yearsAgo] == nil else {
            debugLog("Load already in progress for page \(yearsAgo)")
            return
        }
        
        let currentState = pageStateByYear[yearsAgo] ?? .idle
        switch currentState {
        case .idle, .error(_):
            break
        default:
            debugLog("Load not needed for page \(yearsAgo), state is \(currentState)")
            return
        }
        
        debugLog("Launching load task for page \(yearsAgo)...")
        let loadTask = Task { await loadPageAsync(yearsAgo: yearsAgo) }
        activeLoadTasks[yearsAgo] = loadTask
    }

    private func loadPageAsync(yearsAgo: Int) async {
        let spanStart = Date()

        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            debugLog("Cannot load content without photo library access.")
            TelemetryService.shared.recordSpan(
                name: "loadPage", startTime: spanStart,
                durationMs: Int(Date().timeIntervalSince(spanStart) * 1000),
                attributes: ["years_ago": yearsAgo, "outcome": "denied"], status: .error
            )
            await MainActor.run { pageStateByYear[yearsAgo] = .error(message: "Photo library access required") }
            activeLoadTasks[yearsAgo] = nil
            return
        }

        await MainActor.run { pageStateByYear[yearsAgo] = .loading }
        
        do {
            debugLog("Fetching all items for year \(yearsAgo) (up to limit)...")
            let allItems = try await fetchMediaItems(yearsAgo: yearsAgo, limit: Constants.samplingPoolLimit)
            try Task.checkCancellation()
            
            if allItems.isEmpty {
                debugLog("No photos found for \(yearsAgo) years ago.")
                await MainActor.run { pageStateByYear[yearsAgo] = .empty }
                activeLoadTasks[yearsAgo] = nil
                return
            }
            
            let featuredItem = self.selector.pickFeaturedItem(from: allItems)
            
            var photosToDisplay: [MediaItem]
            if allItems.count > Constants.maxPhotosToDisplay {
                if let featured = featuredItem {
                    let remainingItems = allItems.filter { $0.id != featured.id }
                    var sampledItems = Array(remainingItems.shuffled().prefix(Constants.maxPhotosToDisplay - 1))
                    sampledItems.append(featured)
                    photosToDisplay = sampledItems
                } else {
                    photosToDisplay = Array(allItems.shuffled().prefix(Constants.maxPhotosToDisplay))
                }
            } else {
                photosToDisplay = allItems
            }
            
            let gridItems: [MediaItem]
            if let featured = featuredItem {
                gridItems = photosToDisplay.filter { $0.id != featured.id }
            } else {
                gridItems = photosToDisplay
            }
            
            debugLog("Load complete for \(yearsAgo). Featured: \(featuredItem != nil), Grid: \(gridItems.count) items")
            try Task.checkCancellation()

            let durationMs = Int(Date().timeIntervalSince(spanStart) * 1000)

            TelemetryService.shared.recordSpan(
                name: "loadPage", startTime: spanStart, durationMs: durationMs,
                attributes: [
                    "years_ago": yearsAgo, "outcome": "success",
                    "item_count": allItems.count, "grid_count": gridItems.count,
                    "has_featured": featuredItem != nil
                ]
            )
            TelemetryService.shared.recordHistogram(
                name: "throwbaks.loadPage.duration", value: Double(durationMs),
                attributes: ["years_ago": yearsAgo]
            )
            TelemetryService.shared.incrementCounter(
                name: "throwbaks.photos.displayed", attributes: ["years_ago": yearsAgo]
            )
            TelemetryService.shared.log(
                "loadPage success",
                attributes: ["years_ago": yearsAgo, "item_count": allItems.count, "duration_ms": durationMs]
            )

            await MainActor.run {
                pageStateByYear[yearsAgo] = .loaded(featured: featuredItem, grid: gridItems)
                activeLoadTasks[yearsAgo] = nil
            }
            
        } catch is CancellationError {
            debugLog("Load task cancelled for year \(yearsAgo).")
            TelemetryService.shared.recordSpan(
                name: "loadPage", startTime: spanStart,
                durationMs: Int(Date().timeIntervalSince(spanStart) * 1000),
                attributes: ["years_ago": yearsAgo, "outcome": "cancelled"]
            )
            TelemetryService.shared.log("loadPage cancelled", severity: .warn, attributes: ["years_ago": yearsAgo])
            await MainActor.run {
                if case .loading = pageStateByYear[yearsAgo] { pageStateByYear[yearsAgo] = .idle }
                activeLoadTasks[yearsAgo] = nil
            }
        } catch let error as PhotoError {
            debugLog("Load failed for year \(yearsAgo): \(error.localizedDescription)")
            TelemetryService.shared.recordSpan(
                name: "loadPage", startTime: spanStart,
                durationMs: Int(Date().timeIntervalSince(spanStart) * 1000),
                attributes: ["years_ago": yearsAgo, "outcome": "error", "error": error.localizedDescription],
                status: .error
            )
            TelemetryService.shared.log("loadPage error: \(error.localizedDescription)", severity: .error, attributes: ["years_ago": yearsAgo])
            await MainActor.run {
                pageStateByYear[yearsAgo] = .error(message: error.localizedDescription)
                activeLoadTasks[yearsAgo] = nil
            }
        } catch {
            debugLog("Unexpected load failure for year \(yearsAgo): \(error.localizedDescription)")
            let wrappedError = PhotoError.underlyingPhotoLibraryError(error)
            TelemetryService.shared.recordSpan(
                name: "loadPage", startTime: spanStart,
                durationMs: Int(Date().timeIntervalSince(spanStart) * 1000),
                attributes: ["years_ago": yearsAgo, "outcome": "error", "error": wrappedError.localizedDescription],
                status: .error
            )
            TelemetryService.shared.log("loadPage error: \(wrappedError.localizedDescription)", severity: .error, attributes: ["years_ago": yearsAgo])
            await MainActor.run {
                pageStateByYear[yearsAgo] = .error(message: wrappedError.localizedDescription)
                activeLoadTasks[yearsAgo] = nil
            }
        }
    }

    private func fetchMediaItems(yearsAgo: Int, limit: Int?) async throws -> [MediaItem] {
        let calendar = Calendar.current
        let today = Date()
        
        guard let dateRange = calculateDateRange(yearsAgo: yearsAgo, calendar: calendar, today: today) else {
            throw PhotoError.dateCalculationError(details: "Target date range for \(yearsAgo) years ago")
        }
        
        let options = PHFetchOptions()
        let basePredicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate < %@",
            argumentArray: [dateRange.start, dateRange.end]
        )
        let hiddenPredicate = NSPredicate(format: "isHidden == NO")
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [basePredicate, hiddenPredicate])
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        if let limit = limit, limit > 0 { options.fetchLimit = limit }
        
        let fetchResult = PHAsset.fetchAssets(with: options)
        try Task.checkCancellation()
        
        var items = [MediaItem]()
        var cancelledDuringEnumeration = false
        
        fetchResult.enumerateObjects { asset, _, stopPointer in
            if Task.isCancelled {
                stopPointer.pointee = true
                cancelledDuringEnumeration = true
                return
            }
            items.append(self.factory.createMediaItem(from: asset))
        }
        
        if cancelledDuringEnumeration { try Task.checkCancellation() }
        return items
    }

    func cancelLoad(yearsAgo: Int) {
        debugLog("Requesting cancellation for year \(yearsAgo)...")
        activeLoadTasks[yearsAgo]?.cancel(); activeLoadTasks[yearsAgo] = nil
        Task { await MainActor.run { if case .loading = pageStateByYear[yearsAgo] { pageStateByYear[yearsAgo] = .idle } else if case .loaded(_, let grid) = pageStateByYear[yearsAgo], grid.isEmpty { pageStateByYear[yearsAgo] = .idle } } }
    }

     func retryLoad(yearsAgo: Int) {
         guard case .error = pageStateByYear[yearsAgo] else { debugLog("Retry not needed for year \(yearsAgo), state is not error."); return }
         debugLog("Retrying load for year \(yearsAgo)...")
         activeLoadTasks[yearsAgo]?.cancel(); activeLoadTasks[yearsAgo] = nil
         pageStateByYear[yearsAgo] = .idle
         loadPage(yearsAgo: yearsAgo)
     }

    func triggerPrefetch(around centerYearsAgo: Int) {
        guard initialYearScanComplete else { return }
        let yearsToCheck = [centerYearsAgo + 1, centerYearsAgo - 1].filter { $0 > 0 }
        debugLog("Triggering prefetch check around \(centerYearsAgo). Checking: \(yearsToCheck)")
        for yearToPrefetch in yearsToCheck { prefetchIfNeeded(forYear: yearToPrefetch) }

        // IMPROVEMENT 2: Stop system-level caching for years that are no longer adjacent
        let activeYears = Set(yearsToCheck + [centerYearsAgo])
        let yearsToStop = cachedAssetsByYear.keys.filter { !activeYears.contains($0) }
        for year in yearsToStop {
            guard let assets = cachedAssetsByYear.removeValue(forKey: year) else { continue }
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            imageManager.stopCachingImages(for: assets, targetSize: Constants.prefetchThumbnailSize, contentMode: .aspectFill, options: options)
            debugLog("Stopped system caching for year \(year) (\(assets.count) assets)")
        }
    }
    
    private func startDefinitiveFeaturedImagePrefetchTask(for yearToPrefetch: Int, mainLoadTask: Task<Void, Never>) {
        debugLog("Starting featured image prefetch for \(yearToPrefetch).")
        
        let featuredTask = Task { [weak self] in
            guard let self = self else { return }
            await mainLoadTask.value
            
            guard !Task.isCancelled else {
                debugLog("Featured prefetch cancelled during wait for \(yearToPrefetch)")
                return
            }
            
            let state = await MainActor.run { self.pageStateByYear[yearToPrefetch] }
            
            guard case .loaded(let featuredItem, _) = state, let featured = featuredItem else {
                debugLog("No featured item to prefetch for \(yearToPrefetch)")
                await MainActor.run { self.activeFeaturedPrefetchTasks[yearToPrefetch] = nil }
                return
            }
                        
            self.requestFullSizeImage(for: featured.asset) { image in
                Task { @MainActor in
                    guard !Task.isCancelled else { return }
                    if let loadedImage = image {
                        debugLog("Featured image preloaded for \(yearToPrefetch)")
                        self.preloadedFeaturedImages[yearToPrefetch] = loadedImage
                    } else {
                        debugLog("Failed to preload featured image for \(yearToPrefetch)")
                    }
                    self.activeFeaturedPrefetchTasks[yearToPrefetch] = nil
                }
            }
        }
        activeFeaturedPrefetchTasks[yearToPrefetch] = featuredTask
    }

    private func prefetchIfNeeded(forYear yearToPrefetch: Int) {
        guard availableYearsAgo.contains(yearToPrefetch) else { return }
        let currentState = pageStateByYear[yearToPrefetch] ?? .idle
        guard case .idle = currentState else { return }
        guard activeLoadTasks[yearToPrefetch] == nil else {
            debugLog("Load already in progress for page \(yearToPrefetch)")
            return
        }
        
        debugLog("Prefetching page for \(yearToPrefetch) years ago.")
        let loadTask = Task { await loadPageAsync(yearsAgo: yearToPrefetch) }
        activeLoadTasks[yearToPrefetch] = loadTask
        
        if activeFeaturedPrefetchTasks[yearToPrefetch] == nil && preloadedFeaturedImages[yearToPrefetch] == nil {
            startDefinitiveFeaturedImagePrefetchTask(for: yearToPrefetch, mainLoadTask: loadTask)
        }

        if activePrefetchThumbnailTasks[yearToPrefetch] == nil {
            startThumbnailPrefetchTask(for: yearToPrefetch)
        }
    }
    
    private func startThumbnailPrefetchTask(for yearToPrefetch: Int) {
        debugLog("Starting thumbnail prefetch task for \(yearToPrefetch).")
        
        let thumbnailTask = Task {
            do {
                let initialItems = try await fetchMediaItems(
                    yearsAgo: yearToPrefetch,
                    limit: Constants.initialFetchLimitForLoadPage
                )
                try Task.checkCancellation()
                guard !initialItems.isEmpty else { return }
                
                debugLog("Requesting \(initialItems.count) thumbnails proactively for \(yearToPrefetch)...")

                // IMPROVEMENT 2: Use PHCachingImageManager's system-level pre-decoding
                let assets = initialItems.map { $0.asset }
                let cachingOptions = PHImageRequestOptions()
                cachingOptions.deliveryMode = .opportunistic
                cachingOptions.resizeMode = .fast
                cachingOptions.isNetworkAccessAllowed = true
                await MainActor.run {
                    self.imageManager.startCachingImages(for: assets, targetSize: Constants.prefetchThumbnailSize, contentMode: .aspectFill, options: cachingOptions)
                    self.cachedAssetsByYear[yearToPrefetch] = assets
                    debugLog("Started system caching for year \(yearToPrefetch) (\(assets.count) assets)")
                }

                for item in initialItems {
                    try Task.checkCancellation()
                    requestImage(for: item.asset, targetSize: Constants.prefetchThumbnailSize) { _ in }
                }
                debugLog("Thumbnail requests initiated for \(yearToPrefetch).")
            } catch is CancellationError {
                debugLog("Thumbnail prefetch task cancelled for \(yearToPrefetch).")
            } catch {
                debugLog("Error during thumbnail prefetch for \(yearToPrefetch): \(error.localizedDescription)")
            }
            await MainActor.run { activePrefetchThumbnailTasks[yearToPrefetch] = nil }
        }
        activePrefetchThumbnailTasks[yearToPrefetch] = thumbnailTask
    }

    // MARK: - Progressive Loading Support
    /// Returns a cached thumbnail for the asset if one exists (used for instant placeholder in detail view)
    func cachedThumbnail(for asset: PHAsset) -> UIImage? {
        return imageCacheService.cachedImage(for: asset.localIdentifier, isHighRes: false)
    }

    func getPreloadedFeaturedImage(for yearsAgo: Int) -> UIImage? {
        return preloadedFeaturedImages[yearsAgo]
    }

    // MARK: - Carousel Support

    func getFeaturedItem(for yearsAgo: Int) -> MediaItem? {
        guard case .loaded(let featured, _) = pageStateByYear[yearsAgo] else { return nil }
        return featured
    }

    func loadFeaturedImagesForCarousel(years: [Int]) {
        for year in years {
            loadPage(yearsAgo: year)
            if preloadedFeaturedImages[year] == nil,
               activeFeaturedPrefetchTasks[year] == nil,
               let loadTask = activeLoadTasks[year] {
                startDefinitiveFeaturedImagePrefetchTask(for: year, mainLoadTask: loadTask)
            }
        }
    }

    func requestImage(for asset: PHAsset, targetSize: CGSize, completion: @escaping (UIImage?) -> Void) {
        let assetIdentifier = asset.localIdentifier
        let isHighRes = targetSize == PHImageManagerMaximumSize
        
        if let cachedImage = imageCacheService.cachedImage(for: assetIdentifier, isHighRes: isHighRes) {
            completion(cachedImage)
            return
        }
        
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = isHighRes ? .highQualityFormat : .opportunistic
        options.resizeMode   = isHighRes ? .none              : .fast
        options.isSynchronous = false
        options.version = .current
        
        cancelActiveRequest(for: assetIdentifier)
        
        options.progressHandler = { [weak self] progress, error, stop, info in
            guard let self = self else { return }
            if let error = error {
                debugLog("Image loading error (progress): \(error.localizedDescription) for \(assetIdentifier)")
                if progress < Constants.fullProgress {
                    self.retryImageRequest(for: asset, targetSize: targetSize, completion: completion)
                }
                stop.pointee = true
            }
        }
        
        let requestID = imageManager.requestImage(
            for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options
        ) { [weak self] image, info in
            guard let self = self else { return }
            
            if self.activeRequests[assetIdentifier] == info?[PHImageResultRequestIDKey] as? PHImageRequestID {
                self.activeRequests.removeValue(forKey: assetIdentifier)
            }
            
            let isCancelled = info?[PHImageCancelledKey] as? Bool ?? false
            if isCancelled { completion(nil); return }
            
            if let error = info?[PHImageErrorKey] as? Error {
                debugLog("Image loading error: \(error.localizedDescription) for \(assetIdentifier)")
                completion(nil)
                return
            }
            
            if let image = image {
                self.imageCacheService.cacheImage(image, for: assetIdentifier, isHighRes: isHighRes)
                DispatchQueue.main.async { completion(image) }
            } else {
                DispatchQueue.main.async { completion(nil) }
            }
        }
        
        activeRequests[assetIdentifier] = requestID
    }

    private func retryImageRequest(for asset: PHAsset, targetSize: CGSize, completion: @escaping (UIImage?) -> Void) {
        let assetIdentifier = asset.localIdentifier
        let isHighRes = targetSize == PHImageManagerMaximumSize
        
        debugLog("Retrying image request for asset \(asset.localIdentifier)")
        
        let retryOptions = PHImageRequestOptions()
        retryOptions.isNetworkAccessAllowed = true
        retryOptions.deliveryMode = .highQualityFormat
        retryOptions.resizeMode = .none
        retryOptions.isSynchronous = false
        retryOptions.version = .current
        
        cancelActiveRequest(for: assetIdentifier)
        
        let requestID = imageManager.requestImage(
            for: asset, targetSize: targetSize, contentMode: .aspectFit, options: retryOptions
        ) { [weak self] retryImage, retryInfo in
            guard let self = self else { return }
            
            if self.activeRequests[assetIdentifier] == retryInfo?[PHImageResultRequestIDKey] as? PHImageRequestID {
                self.activeRequests.removeValue(forKey: assetIdentifier)
            }
            
            let isCancelled = retryInfo?[PHImageCancelledKey] as? Bool ?? false
            if isCancelled { completion(nil); return }
            
            if let retryError = retryInfo?[PHImageErrorKey] as? Error {
                debugLog("Retry failed for asset \(assetIdentifier): \(retryError.localizedDescription)")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            if let retryImage = retryImage {
                debugLog("Retry successful for asset \(assetIdentifier)")
                self.imageCacheService.cacheImage(retryImage, for: assetIdentifier, isHighRes: isHighRes)
                DispatchQueue.main.async { completion(retryImage) }
            } else {
                DispatchQueue.main.async { completion(nil) }
            }
        }
        activeRequests[assetIdentifier] = requestID
    }

    private func cancelActiveRequest(for assetIdentifier: String) {
        if let existingRequestID = activeRequests[assetIdentifier] {
            imageManager.cancelImageRequest(existingRequestID)
            activeRequests.removeValue(forKey: assetIdentifier)
        }
    }
    
    internal func clearImageCache() {
        debugLog("Clearing image cache and preloaded featured images.")
        preloadedFeaturedImages.removeAll()
        imageCacheService.clearCache()
    }

    func requestLivePhoto(for asset: PHAsset,
                          targetSize: CGSize = PHImageManagerMaximumSize,
                          completion: @escaping @MainActor (PHLivePhoto?) -> Void) {

        guard asset.mediaSubtypes.contains(.photoLive) else {
            completion(nil)
            return
        }

        let assetIdentifier = asset.localIdentifier

        if let cachedLivePhoto = imageCacheService.cachedLivePhoto(for: assetIdentifier) {
            completion(cachedLivePhoto)
            return
        }

        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.version = .current

        imageManager.requestLivePhoto(for: asset, targetSize: targetSize,
                                   contentMode: .aspectFit, options: options) { [weak self] livePhoto, info in
            guard let self = self else { return }

            let isCancelled = info?[PHImageCancelledKey] as? Bool ?? false
            if isCancelled { completion(nil); return }

            if let error = info?[PHImageErrorKey] as? Error {
                debugLog("Live Photo loading error: \(error.localizedDescription) for \(assetIdentifier)")
                completion(nil)
                return
            }

            guard let fetchedLivePhoto = livePhoto else {
                completion(nil)
                return
            }

            self.imageCacheService.cacheLivePhoto(fetchedLivePhoto, for: assetIdentifier)
            completion(fetchedLivePhoto)
        }
    }
    
    func requestFullImageData(for asset: PHAsset) async -> Data? {
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .none
            options.isSynchronous = false
            
            imageManager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    debugLog("Error fetching full image data: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                } else if let data = data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func requestVideoURL(for asset: PHAsset) async -> URL? {
        guard asset.mediaType == .video else { return nil }
        
        return await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.version = .current
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .automatic
            
            imageManager.requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    debugLog("Error requesting AVAsset for \(asset.localIdentifier): \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                guard let urlAsset = avAsset as? AVURLAsset else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: urlAsset.url)
            }
        }
    }

    // IMPROVEMENT 4: Use requestImage with screen-resolution target instead of requestImageDataAndOrientation.
    // This avoids loading the full raw image data (20-50MB for 48MP photos) into memory.
    // The raw data path (requestFullImageData) is still used for sharing/export.
    func requestFullSizeImage(for asset: PHAsset, completion: @escaping (UIImage?) -> Void) {
        let assetIdentifier = asset.localIdentifier
        let isHighRes = true
        
        if let cachedImage = imageCacheService.cachedImage(for: assetIdentifier, isHighRes: isHighRes) {
            completion(cachedImage)
            return
        }
        
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isSynchronous = false
        options.version = .current
        
        cancelActiveRequest(for: assetIdentifier)
        
        let requestID = imageManager.requestImage(
            for: asset,
            targetSize: displayImageSize,
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, info in
            guard let self = self else { return }
            
            if self.activeRequests[assetIdentifier] == info?[PHImageResultRequestIDKey] as? PHImageRequestID {
                self.activeRequests.removeValue(forKey: assetIdentifier)
            }
            
            let isCancelled = info?[PHImageCancelledKey] as? Bool ?? false
            if isCancelled { completion(nil); return }
            
            if let error = info?[PHImageErrorKey] as? Error {
                debugLog("Error loading display image: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            if let image = image {
                self.imageCacheService.cacheImage(image, for: assetIdentifier, isHighRes: isHighRes)
                DispatchQueue.main.async { completion(image) }
            } else {
                DispatchQueue.main.async { completion(nil) }
            }
        }
        
        activeRequests[assetIdentifier] = requestID
    }

    // MARK: - Limited Library Handling
    func presentLimitedLibraryPicker() { debugLog("Placeholder: Would present limited library picker here.") }

    // MARK: - Address Lookup
    private let geocoder = CLGeocoder()

    func placemark(for asset: PHAsset) async -> String {
        let id = asset.localIdentifier

        if let cached = imageCacheService.cachedPlacemark(for: id) { return cached }

        let address: String
        if let loc = asset.location {
            do {
                let places = try await geocoder.reverseGeocodeLocation(loc)
                let comps = [places.first?.name,
                             places.first?.locality,
                             places.first?.administrativeArea].compactMap { $0 }
                address = comps.isEmpty ? "Nearby Location" : comps.joined(separator: ", ")
            } catch {
                address = "Address not found"
            }
        } else {
            address = "No Location Data"
        }

        imageCacheService.cachePlacemark(address, for: id)
        return address
    }

    private func calculateDateRange(yearsAgo: Int, calendar: Calendar, today: Date) -> (start: Date, end: Date)? {
        var components = calendar.dateComponents([.year, .month, .day], from: today)
        components.year = (components.year ?? calendar.component(.year, from: today)) - yearsAgo
        
        guard let targetDate = calendar.date(from: components) else { return nil }
        let startOfDay = calendar.startOfDay(for: targetDate)
        guard let endOfDay = calendar.date(byAdding: .day, value: Constants.daysToAddForDateRangeEnd, to: startOfDay) else { return nil }
        return (startOfDay, endOfDay)
    }

    func performCleanup() {
        debugLog("Performing ViewModel cleanup...")
        activeLoadTasks.values.forEach { $0.cancel() }
        activeLoadTasks.removeAll()
        activePrefetchThumbnailTasks.values.forEach { $0.cancel() }
        activePrefetchThumbnailTasks.removeAll()
        activeFeaturedPrefetchTasks.values.forEach { $0.cancel() }
        activeFeaturedPrefetchTasks.removeAll()
        backgroundYearScanTask?.cancel()
        backgroundYearScanTask = nil
        preloadedFeaturedImages.removeAll()
        imageManager.stopCachingImagesForAllAssets() // IMPROVEMENT 2: Clean up system caching
        cachedAssetsByYear.removeAll()
        debugLog("ViewModel cleanup complete.")
    }

    deinit {
        debugLog("PhotoViewModel deinit.")
        backgroundYearScanTask?.cancel()
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
