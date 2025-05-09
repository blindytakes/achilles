// Throwbaks/Achilles/ViewModels/PhotoViewModel.swift

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

        // Image Sizes
        static let defaultThumbnailSize = CGSize(width: 250, height: 250)
        static let prefetchThumbnailSize = CGSize(width: 200, height: 200) // Use this for proactive thumbnail loading

        // Date Calculations
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
    @Published var dismissedSplashForYearsAgo: Set<Int> = []
    @Published var gridAnimationDone: Set<Int> = []
    @Published var gridDateAnimationsCompleted: Set<Int> = []
    @Published var featuredTextAnimationsCompleted: Set<Int> = []
    @Published var featuredImageAnimationsCompleted: Set<Int> = []

    // MARK: - Internal Properties
    // Task Management
    private var activeLoadTasks: [Int: Task<Void, Never>] = [:]
    private var activeGridLoadTasks: [Int: Task<Void, Never>] = [:]
    private var activePrefetchThumbnailTasks: [Int: Task<Void, Never>] = [:]
    private var activeFeaturedPrefetchTasks: [Int: Task<Void, Never>] = [:]
    private var backgroundYearScanTask: Task<Void, Never>? = nil // Task for Phase 2 scan

    // Preloaded Data Storage
    private var preloadedFeaturedImages: [Int: UIImage] = [:]

    var thumbnailSize = Constants.defaultThumbnailSize

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
    }

    // MARK: - Animation State Handling
    func shouldAnimate(yearsAgo: Int) -> Bool {
        !featuredTextAnimationsCompleted.contains(yearsAgo)
    }
    func markAnimated(yearsAgo: Int) {
        featuredTextAnimationsCompleted.insert(yearsAgo)
        print("✍️ Marked TEXT animation done for \(yearsAgo)")
    }
    func shouldAnimateImageEffects(yearsAgo: Int) -> Bool {
        !featuredImageAnimationsCompleted.contains(yearsAgo)
    }
    func markImageEffectsAnimated(yearsAgo: Int) {
        featuredImageAnimationsCompleted.insert(yearsAgo)
        print("🖼️ Marked IMAGE effects animation done for \(yearsAgo)")
    }
    func markSplashDismissed(for yearsAgo: Int) {
        dismissedSplashForYearsAgo.insert(yearsAgo)
    }

    // MARK: - Authorization Handling
    func checkAuthorization() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        handleAuthorization(status: status) // Use helper
    }

    private func handleAuthorization(status: PHAuthorizationStatus) {
         self.authorizationStatus = status
         switch status {
         case .authorized, .limited:
             print("Photo Library access status: \(status)")
             // Start the phased scanning process if needed
             if !initialYearScanComplete && backgroundYearScanTask == nil { // Check background task too
                  Task { await startYearScanningProcess() } // Call new process starter
             }
         case .restricted, .denied:
             print("Photo Library access restricted or denied.")
             // Clear state and cancel any running scan
             self.pageStateByYear = [:]
             self.availableYearsAgo = []
             self.initialYearScanComplete = true // Mark complete (with no results)
             backgroundYearScanTask?.cancel(); backgroundYearScanTask = nil // Cancel background scan
         case .notDetermined:
             print("Requesting Photo Library access...")
             requestAuthorization()
         @unknown default:
             print("Unknown Photo Library authorization status.")
             self.initialYearScanComplete = true
             backgroundYearScanTask?.cancel(); backgroundYearScanTask = nil // Cancel background scan
         }
     }

    private func requestAuthorization() {
        Task {
            let requestedStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            // Switch back to main thread to update published properties
            await MainActor.run {
                // Use the handler function to process the new status
                self.handleAuthorization(status: requestedStatus)
            }
        }
    }

    // MARK: - Content Loading & Prefetching

    // --- Phased Year Scanning (Error Handling Fixed) ---
    private func startYearScanningProcess() async {
        // Don’t rerun Phase 1 if it’s already done
        guard !initialYearScanComplete else {
            print("Initial year scan (Phase 1) already complete.")
            return
        }
        // Ensure we have library permission
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            print("Cannot scan for years without photo library access.")
            await MainActor.run {
                self.initialYearScanComplete = true
            }
            return
        }
        // Cancel any in-flight Phase 2 task
        backgroundYearScanTask?.cancel()
        backgroundYearScanTask = nil

        // MARK: Phase 1 (foreground)
        let initialRange = 1...Constants.initialScanPhaseYears
        print("🚀 Starting Phase 1 scan for years: \(initialRange)")

        var phase1Error: Error? = nil
        var initialYearsFound: [Int] = []

        do {
            initialYearsFound = try await scanYearsInRange(range: initialRange)
            print("✅ Phase 1 scan complete. Found years: \(initialYearsFound.sorted())")
        } catch is CancellationError {
            print("🚫 Phase 1 scan cancelled.")
            return
        } catch {
            print("❌ Error during Phase 1 scan: \(error.localizedDescription)")
            phase1Error = error
        }

        // Publish Phase 1 results
        await MainActor.run {
            self.availableYearsAgo = initialYearsFound.sorted()
            self.initialYearScanComplete = true
            if let error = phase1Error {
                print("⚠️ Phase 1 completed with error: \(error.localizedDescription)")
            }
        }

        // MARK: Phase 2 (background)
        let remainingRange = (Constants.initialScanPhaseYears + 1)...Constants.maxYearsToScanTotal
        guard !remainingRange.isEmpty else {
            print("ℹ️ No remaining years to scan in Phase 2.")
            return
        }

        print("⏳ Starting Phase 2 background scan for years: \(remainingRange)")

        backgroundYearScanTask = Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }

            do {
                // 1) Perform the scan into a local constant
                let foundYears = try await self.scanYearsInRange(range: remainingRange)
                try Task.checkCancellation()
                print("✅ Phase 2 scan complete. Found additional years: \(foundYears.sorted())")

                // 2) Merge and publish on the Main Actor
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    let combined = Set(self.availableYearsAgo + foundYears)
                    self.availableYearsAgo = Array(combined).sorted()
                    print("🔄 Combined available years: \(self.availableYearsAgo)")
                }

            } catch is CancellationError {
                print("🚫 Phase 2 scan task cancelled.")
            } catch {
                print("❌ Error during Phase 2 background scan: \(error.localizedDescription)")
            }

            // 3) Always clear the task reference on the Main Actor
            await MainActor.run {
                self.backgroundYearScanTask = nil
            }
        }
    }


    // Helper function to scan a specific range of years
    private func scanYearsInRange(range: ClosedRange<Int>) async throws -> [Int] {
        var foundYears: [Int] = []
        let calendar = Calendar.current
        let today = Date()
        print("🔍 Scanning range: \(range)...")
        for yearsAgoValue in range {
            try Task.checkCancellation()
            guard let targetDateRange = calculateDateRange(yearsAgo: yearsAgoValue, calendar: calendar, today: today) else {
                print("⚠️ Skipping year \(yearsAgoValue) due to date calculation error."); continue
            }
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", targetDateRange.start as NSDate, targetDateRange.end as NSDate)
            fetchOptions.fetchLimit = Constants.yearCheckFetchLimit
            let fetchResult = PHAsset.fetchAssets(with: fetchOptions) // This is synchronous but fast enough for check
            if fetchResult.firstObject != nil {
                 foundYears.append(yearsAgoValue)
            }
        }
        print("🔍 Finished scanning range: \(range). Found: \(foundYears.count > 0 ? foundYears.sorted() : [])")
        return foundYears
    }

    /// Public wrapper to launch the async task for loading a page
    func loadPage(yearsAgo: Int) {
        // Prevent starting if already loading
        guard activeLoadTasks[yearsAgo] == nil else {
            print("⏳ Load already in progress for page \(yearsAgo)")
            return
        }
        
        // Only proceed if state is idle or error
        let currentState = pageStateByYear[yearsAgo] ?? .idle
        switch currentState {
        case .idle, .error(_):
            break    // allowed to start loading
        default:
            print("ℹ️ Load not needed for page \(yearsAgo), state is \(currentState)")
            return
        }
        
        // Launch the load task
        print("🚀 Launching load task for page \(yearsAgo)...")
        let loadTask = Task { await loadPageAsync(yearsAgo: yearsAgo) }
        activeLoadTasks[yearsAgo] = loadTask
    }

    // Asynchronous loading logic for a specific year page
    private func loadPageAsync(yearsAgo: Int) async {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            print("🚫 Cannot load page \(yearsAgo) - authorization denied.")
            await MainActor.run { pageStateByYear[yearsAgo] = .error(message: "Photo Library access denied."); activeLoadTasks[yearsAgo] = nil }
            return
        }
        await MainActor.run { pageStateByYear[yearsAgo] = .loading }; print("⬆️ Loading page for \(yearsAgo) years ago...")
        var featuredItem: MediaItem? = nil
        do {
            // Phase 1
            print("⏳ Phase 1: Fetching initial items for year \(yearsAgo)")
            let initialItems = try await fetchMediaItems(yearsAgo: yearsAgo, limit: Constants.initialFetchLimitForLoadPage)
            try Task.checkCancellation()
            if initialItems.isEmpty {
                print("✅ Phase 1 Load complete for \(yearsAgo) - Empty."); await MainActor.run { pageStateByYear[yearsAgo] = .empty }; activeLoadTasks[yearsAgo] = nil; return
            }
            featuredItem = self.selector.pickFeaturedItem(from: initialItems)
            print("✅ Phase 1 Load complete for \(yearsAgo). Featured item \(featuredItem == nil ? "not found" : "found").")
            await MainActor.run { pageStateByYear[yearsAgo] = .loaded(featured: featuredItem, grid: []) }

            // Phase 2
            print("⏳ Phase 2: Launching background task for full grid for year \(yearsAgo)")
            activeGridLoadTasks[yearsAgo]?.cancel()
            let gridTask = Task.detached(priority: .background) { [weak self] in
                guard let self = self else { return }
                do {
                    let allItems = try await self.fetchMediaItems(yearsAgo: yearsAgo, limit: nil)
                    try Task.checkCancellation()
                    let gridItems = allItems.filter { $0.id != featuredItem?.id }
                    print("✅ Phase 2 Load complete for \(yearsAgo). Found \(gridItems.count) grid items.")
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        if case .loaded(let currentFeatured, _) = self.pageStateByYear[yearsAgo] { self.pageStateByYear[yearsAgo] = .loaded(featured: currentFeatured, grid: gridItems) }
                        else { print("⚠️ State changed before grid load finished for year \(yearsAgo).") }
                        self.activeGridLoadTasks[yearsAgo] = nil
                    }
                } catch is CancellationError { print("🚫 Grid load task cancelled for year \(yearsAgo)."); await MainActor.run { self.activeGridLoadTasks[yearsAgo] = nil } }
                  catch { print("❌ Error during Phase 2 grid load for year \(yearsAgo): \(error.localizedDescription)"); await MainActor.run { self.activeGridLoadTasks[yearsAgo] = nil } }
            }
            activeGridLoadTasks[yearsAgo] = gridTask

        } catch is CancellationError {
             print("🚫 Load task cancelled during Phase 1 for year \(yearsAgo).")
             await MainActor.run { if case .loading = pageStateByYear[yearsAgo] { pageStateByYear[yearsAgo] = .idle }; activeLoadTasks[yearsAgo] = nil; activeGridLoadTasks[yearsAgo]?.cancel(); activeGridLoadTasks[yearsAgo] = nil }
        } catch let error as PhotoError {
            print("❌ Load failed during Phase 1 for year \(yearsAgo): \(error.localizedDescription)")
            await MainActor.run { pageStateByYear[yearsAgo] = .error(message: error.localizedDescription); activeLoadTasks[yearsAgo] = nil }
        } catch {
            print("❌ Unexpected load failure during Phase 1 for year \(yearsAgo): \(error.localizedDescription)")
            let wrappedError = PhotoError.underlyingPhotoLibraryError(error)
            await MainActor.run { pageStateByYear[yearsAgo] = .error(message: wrappedError.localizedDescription); activeLoadTasks[yearsAgo] = nil }
        }
        await MainActor.run { activeLoadTasks[yearsAgo] = nil }
    }

    // Helper to fetch MediaItems
    private func fetchMediaItems(yearsAgo: Int, limit: Int?) async throws -> [MediaItem] {
        let calendar = Calendar.current
        let today = Date()
        
        // Get date range for the specified year
        guard let dateRange = calculateDateRange(yearsAgo: yearsAgo, calendar: calendar, today: today) else {
            throw PhotoError.dateCalculationError(details: "Target date range for \(yearsAgo) years ago")
        }
        
        // Configure fetch options
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate < %@",
            argumentArray: [dateRange.start, dateRange.end]
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        // Apply limit if provided
        if let limit = limit, limit > 0 {
            options.fetchLimit = limit
        }
        
        // Fetch assets and check for cancellation
        let fetchResult = PHAsset.fetchAssets(with: options)
        try Task.checkCancellation()
        
        // Convert assets to media items
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
        
        // Final cancellation check
        if cancelledDuringEnumeration {
            try Task.checkCancellation()
        }
        
        return items
    }

    // Cancel loading for a specific year
    func cancelLoad(yearsAgo: Int) {
        print("🚫 Requesting cancellation for year \(yearsAgo)...")
        activeLoadTasks[yearsAgo]?.cancel(); activeLoadTasks[yearsAgo] = nil
        activeGridLoadTasks[yearsAgo]?.cancel(); activeGridLoadTasks[yearsAgo] = nil
        Task { await MainActor.run { if case .loading = pageStateByYear[yearsAgo] { pageStateByYear[yearsAgo] = .idle } else if case .loaded(_, let grid) = pageStateByYear[yearsAgo], grid.isEmpty { pageStateByYear[yearsAgo] = .idle } } }
    }

    // Retry loading for a specific year
     func retryLoad(yearsAgo: Int) {
         guard case .error = pageStateByYear[yearsAgo] else { print("ℹ️ Retry not needed for year \(yearsAgo), state is not error."); return }
         print("🔁 Retrying load for year \(yearsAgo)...")
         activeLoadTasks[yearsAgo]?.cancel(); activeLoadTasks[yearsAgo] = nil
         activeGridLoadTasks[yearsAgo]?.cancel(); activeGridLoadTasks[yearsAgo] = nil
         pageStateByYear[yearsAgo] = .idle
         loadPage(yearsAgo: yearsAgo)
     }

    // Trigger pre-fetching for adjacent years
    func triggerPrefetch(around centerYearsAgo: Int) {
        guard initialYearScanComplete else { return }
        let yearsToCheck = [centerYearsAgo + 1, centerYearsAgo - 1].filter { $0 > 0 }; print("⚡️ Triggering prefetch check around \(centerYearsAgo). Checking: \(yearsToCheck)")
        for yearToPrefetch in yearsToCheck {
            guard availableYearsAgo.contains(yearToPrefetch) else { continue }
            let currentState = pageStateByYear[yearToPrefetch] ?? .idle; guard case .idle = currentState else { continue }
            guard activeLoadTasks[yearToPrefetch] == nil else { continue }
            print("⚡️ Prefetching page for \(yearToPrefetch) years ago."); loadPage(yearsAgo: yearToPrefetch)
            if activePrefetchThumbnailTasks[yearToPrefetch] == nil {
                 print("⚡️ Starting thumbnail prefetch task for \(yearToPrefetch).")
                 let thumbnailTask = Task {
                     do { let initialItems = try await fetchMediaItems(yearsAgo: yearToPrefetch, limit: Constants.initialFetchLimitForLoadPage); try Task.checkCancellation(); guard !initialItems.isEmpty else { return }; print("⚡️ Requesting \(initialItems.count) thumbnails proactively for \(yearToPrefetch)..."); for item in initialItems { try Task.checkCancellation(); requestImage(for: item.asset, targetSize: Constants.prefetchThumbnailSize) { _ in } }; print("⚡️ Thumbnail requests initiated for \(yearToPrefetch).") }
                     catch is CancellationError { print("🚫 Thumbnail prefetch task cancelled for \(yearToPrefetch).") } catch { print("❌ Error during thumbnail prefetch task for \(yearToPrefetch): \(error.localizedDescription)") }
                     await MainActor.run { activePrefetchThumbnailTasks[yearToPrefetch] = nil }
                 }; activePrefetchThumbnailTasks[yearToPrefetch] = thumbnailTask
            } else { print("⚡️ Thumbnail prefetch task already active for \(yearToPrefetch).") }
            if activeFeaturedPrefetchTasks[yearToPrefetch] == nil && preloadedFeaturedImages[yearToPrefetch] == nil {
                 print("⚡️ Starting featured image prefetch task for \(yearToPrefetch).")
                 let featuredTask = Task { [weak self] in guard let self = self else { return }; do { let initialItems = try await self.fetchMediaItems(yearsAgo: yearToPrefetch, limit: Constants.initialFetchLimitForLoadPage); try Task.checkCancellation(); guard let featured = self.selector.pickFeaturedItem(from: initialItems) else { print("⚡️ No featured item found to preload for \(yearToPrefetch)."); return }; try Task.checkCancellation(); print("⚡️ Requesting full-size image for featured item \(featured.id) for year \(yearToPrefetch)..."); self.requestFullSizeImage(for: featured.asset) { image in Task { await MainActor.run { guard !Task.isCancelled else { print("🚫 Featured prefetch task cancelled before storing image for \(yearToPrefetch)."); return }; if let loadedImage = image { print("✅ Featured image preloaded successfully for \(yearToPrefetch). Storing."); self.preloadedFeaturedImages[yearToPrefetch] = loadedImage } else { print("⚠️ Featured image preloading returned nil for \(yearToPrefetch).") } } } } }
                     catch is CancellationError { print("🚫 Featured prefetch task cancelled for \(yearToPrefetch).") } catch { print("❌ Error during featured prefetch task for \(yearToPrefetch): \(error.localizedDescription)") }
                     await MainActor.run { self.activeFeaturedPrefetchTasks[yearToPrefetch] = nil }
                 }; activeFeaturedPrefetchTasks[yearToPrefetch] = featuredTask
            } else { print("⚡️ Featured image prefetch task already active or image already preloaded for \(yearToPrefetch).") }
        }
    }

    // Function to get preloaded featured image
    func getPreloadedFeaturedImage(for yearsAgo: Int) -> UIImage? {
        return preloadedFeaturedImages[yearsAgo]
    }

    func requestImage(for asset: PHAsset, targetSize: CGSize, completion: @escaping (UIImage?) -> Void) {
        let assetIdentifier = asset.localIdentifier
        let isHighRes = targetSize == PHImageManagerMaximumSize
        
        // Check cache first
        if let cachedImage = imageCacheService.cachedImage(for: assetIdentifier, isHighRes: isHighRes) {
            print("✅ Using cached \(isHighRes ? "high-res" : "thumbnail") image for asset: \(assetIdentifier)")
            completion(cachedImage)
            return
        }
        
        print("⬆️ Requesting \(isHighRes ? "high-res" : "thumbnail") image for asset: \(assetIdentifier)")
        
        // Configure request options
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = isHighRes ? .highQualityFormat : .opportunistic
        options.resizeMode = isHighRes ? .none : .fast
        options.isSynchronous = false
        options.version = .current
        
        // Cancel any existing request
        cancelActiveRequest(for: assetIdentifier)
        
        // Configure progress handler
        options.progressHandler = { [weak self] progress, error, stop, info in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Image loading error (progress): \(error.localizedDescription) for \(assetIdentifier)")
                if progress < Constants.fullProgress {
                    print("🔄 Retrying image request due to progress error for \(assetIdentifier)")
                    self.retryImageRequest(for: asset, targetSize: targetSize, completion: completion)
                }
                stop.pointee = true
            }
        }
        
        // Make the request
        let requestID = imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, info in
            guard let self = self else { return }
            
            // Clean up the request
            if self.activeRequests[assetIdentifier] == info?[PHImageResultRequestIDKey] as? PHImageRequestID {
                self.activeRequests.removeValue(forKey: assetIdentifier)
            }
            
            // Check for cancellation
            let isCancelled = info?[PHImageCancelledKey] as? Bool ?? false
            if isCancelled {
                print("🚫 Image request cancelled for \(assetIdentifier).")
                completion(nil)
                return
            }
            
            // Check for errors
            if let error = info?[PHImageErrorKey] as? Error {
                print("❌ Image loading error (completion): \(error.localizedDescription) for \(assetIdentifier)")
                completion(nil)
                return
            }
            
            // Process the result
            if let image = image {
                print("✅ Image loaded successfully for \(assetIdentifier)")
                self.imageCacheService.cacheImage(image, for: assetIdentifier, isHighRes: isHighRes)
                DispatchQueue.main.async {
                    completion(image)
                }
            } else {
                print("⚠️ Image was nil, but no error reported for asset \(assetIdentifier)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
        
        // Store the request ID
        activeRequests[assetIdentifier] = requestID
        print("⏳ Stored request ID \(requestID) for asset \(assetIdentifier)")
    }

    private func retryImageRequest(for asset: PHAsset, targetSize: CGSize, completion: @escaping (UIImage?) -> Void) {
        let assetIdentifier = asset.localIdentifier
        let isHighRes = targetSize == PHImageManagerMaximumSize
        
        print("🔄 Executing retry logic for asset \(asset.localIdentifier)")
        
        // Configure retry options
        let retryOptions = PHImageRequestOptions()
        retryOptions.isNetworkAccessAllowed = true
        retryOptions.deliveryMode = .highQualityFormat
        retryOptions.resizeMode = .none
        retryOptions.isSynchronous = false
        retryOptions.version = .current
        
        // Cancel any existing request
        cancelActiveRequest(for: assetIdentifier)
        
        // Make the retry request
        let requestID = imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: retryOptions
        ) { [weak self] retryImage, retryInfo in
            guard let self = self else { return }
            
            // Clean up the request
            if self.activeRequests[assetIdentifier] == retryInfo?[PHImageResultRequestIDKey] as? PHImageRequestID {
                self.activeRequests.removeValue(forKey: assetIdentifier)
            }
            
            // Check for cancellation
            let isCancelled = retryInfo?[PHImageCancelledKey] as? Bool ?? false
            if isCancelled {
                print("🚫 Retry request cancelled for \(assetIdentifier).")
                completion(nil)
                return
            }
            
            // Check for errors
            if let retryError = retryInfo?[PHImageErrorKey] as? Error {
                print("❌❌ Retry failed for asset \(assetIdentifier): \(retryError.localizedDescription)")
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            // Process the result
            if let retryImage = retryImage {
                print("✅✅ Retry successful for asset \(assetIdentifier)")
                self.imageCacheService.cacheImage(retryImage, for: assetIdentifier, isHighRes: isHighRes)
                DispatchQueue.main.async {
                    completion(retryImage)
                }
            } else {
                print("⚠️⚠️ Retry resulted in nil image for asset \(assetIdentifier)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
        
        // Store the request ID
        activeRequests[assetIdentifier] = requestID
        print("⏳ Stored retry request ID \(requestID) for asset \(assetIdentifier)")
    }

    private func cancelActiveRequest(for assetIdentifier: String) {
        if let existingRequestID = activeRequests[assetIdentifier] {
            print("🚫 Cancelling existing request \(existingRequestID) for asset \(assetIdentifier)")
            imageManager.cancelImageRequest(existingRequestID)
            activeRequests.removeValue(forKey: assetIdentifier)
        }
    }
    
    internal func clearImageCache() {
        print("🧹 Clearing preloaded featured images along with cache.")
        preloadedFeaturedImages.removeAll()
        imageCacheService.clearCache()
    }

    func requestLivePhoto(for asset: PHAsset,
                          targetSize: CGSize = PHImageManagerMaximumSize, // Default to full size
                          completion: @escaping @MainActor (PHLivePhoto?) -> Void) { // Ensure completion on MainActor

        // 1. Validate Asset Type
        guard asset.mediaSubtypes.contains(.photoLive) else {
            print("⚠️ [VM] Attempted to request Live Photo for a non-Live Photo asset: \(asset.localIdentifier)")
            // No need for Task{} here as completion is already @MainActor
            completion(nil)
            return
        }

        let assetIdentifier = asset.localIdentifier

        // 2. Check Cache First
        if let cachedLivePhoto = imageCacheService.cachedLivePhoto(for: assetIdentifier) {
            print("✅ [VM] Using cached Live Photo for asset: \(assetIdentifier)")
            // No need for Task{} here as completion is already @MainActor
            completion(cachedLivePhoto)
            return // Return early if cache hit
        }

        // 3. Prepare Request Options (Cache Miss)
        print("⬆️ [VM] Requesting Live Photo object (cache miss) for asset: \(assetIdentifier)")
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat // Prefer high quality for detail view
        options.isNetworkAccessAllowed = true // Allow downloading from iCloud if needed
        options.version = .current

        // 4. Make Request via PHImageManager
        // Using the viewModel's instance: self.imageManager
        imageManager.requestLivePhoto(for: asset,
                                   targetSize: targetSize,
                                   contentMode: .aspectFit, // Or .aspectFill depending on UI needs
                                   options: options) { [weak self] livePhoto, info in
            // We are likely already on the main thread for the *final* result handler,
            // but marking completion @MainActor provides extra safety/clarity.

            guard let self = self else { return } // Ensure ViewModel hasn't been deallocated

            // 5. Handle Completion Info Dictionary
            let isCancelled = info?[PHImageCancelledKey] as? Bool ?? false
            let error = info?[PHImageErrorKey] as? Error

            // Check for cancellation
            if isCancelled {
                print("🚫 [VM] Live Photo request cancelled for \(assetIdentifier).")
                completion(nil) // Completion is already @MainActor
                return
            }

            // Check for errors
            if let error = error {
                print("❌ [VM] Live Photo loading error: \(error.localizedDescription) for \(assetIdentifier)")
                completion(nil) // Completion is already @MainActor
                return
            }

            // Check if result is valid
            guard let fetchedLivePhoto = livePhoto else {
                // This case might happen, though usually an error is provided.
                print("⚠️ [VM] Live Photo result was nil, but no error reported for asset \(assetIdentifier)")
                completion(nil) // Completion is already @MainActor
                return
            }

            // 6. Success: Cache and Complete
            print("✅ [VM] Live Photo loaded successfully for \(assetIdentifier)")
            // Cache the successfully fetched Live Photo
            self.imageCacheService.cacheLivePhoto(fetchedLivePhoto, for: assetIdentifier)
            // Call the completion handler with the result
            completion(fetchedLivePhoto) // Completion is already @MainActor
        }
    }
    
    // End of requestLivePhoto function
    
    
    func requestFullImageData(for asset: PHAsset) async -> Data? {
        return await withCheckedContinuation { continuation in
            // Configure options
            let options = PHImageRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .none
            options.isSynchronous = false
            
            print("⬆️ Requesting full image data for sharing asset \(asset.localIdentifier)")
            
            imageManager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                // Handle errors
                if let error = info?[PHImageErrorKey] as? Error {
                    print("❌ Error fetching full image data: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
                // Handle successful data
                else if let data = data {
                    print("✅ Full image data fetched for \(asset.localIdentifier)")
                    continuation.resume(returning: data)
                }
                // Handle nil data with no error
                else {
                    print("⚠️ Full image data was nil for \(asset.localIdentifier)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func requestVideoURL(for asset: PHAsset) async -> URL? {
        // Only proceed if it's a video asset
        guard asset.mediaType == .video else { return nil }
        
        return await withCheckedContinuation { continuation in
            // Configure options
            let options = PHVideoRequestOptions()
            options.version = .current
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .automatic
            
            print("⬆️ Requesting AVAsset for video \(asset.localIdentifier)")
            
            imageManager.requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                // Handle errors
                if let error = info?[PHImageErrorKey] as? Error {
                    print("❌ Error requesting AVAsset for \(asset.localIdentifier): \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                // Check if asset is URL-based
                guard let urlAsset = avAsset as? AVURLAsset else {
                    print("⚠️ Requested AVAsset is not AVURLAsset for \(asset.localIdentifier)")
                    continuation.resume(returning: nil)
                    return
                }
                
                print("✅ AVAsset URL fetched for \(asset.localIdentifier)")
                continuation.resume(returning: urlAsset.url)
            }
        }
    }

    func requestFullSizeImage(for asset: PHAsset, completion: @escaping (UIImage?) -> Void) {
        let assetIdentifier = asset.localIdentifier
        let isHighRes = true
        
        // Check cache first
        if let cachedImage = imageCacheService.cachedImage(for: assetIdentifier, isHighRes: isHighRes) {
            print("✅ [VM] Using cached full-size image for asset: \(assetIdentifier)")
            completion(cachedImage)
            return
        }
        
        print("⬆️ [VM] Requesting full-size image data for \(assetIdentifier)")
        
        // Configure request options
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.isSynchronous = false
        options.version = .current
        options.progressHandler = { _,_,_,_ in }
        
        let _ = imageManager.requestImageDataAndOrientation(for: asset, options: options) { [weak self] data, _, _, info in
            guard let self = self else { return }
            
            // Check for cancellation
            let isCancelled = info?[PHImageCancelledKey] as? Bool ?? false
            if isCancelled {
                print("🚫 [VM] Full-size request cancelled for \(assetIdentifier).")
                completion(nil)
                return
            }
            
            // Check for errors
            if let error = info?[PHImageErrorKey] as? Error {
                print("❌ [VM] Error loading full-size image: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            // Process the data
            guard let data = data, let image = UIImage(data: data) else {
                print("⚠️ [VM] Full-size image data invalid for asset \(assetIdentifier)")
                completion(nil)
                return
            }
            
            print("✅ [VM] Full-size image loaded successfully for \(assetIdentifier)")
            self.imageCacheService.cacheImage(image, for: assetIdentifier, isHighRes: isHighRes)
            completion(image)
        }
    }

    // MARK: - Limited Library Handling
    func presentLimitedLibraryPicker() { print("⚠️ Placeholder: Would present limited library picker here.") }

    // MARK: - Private Helper Functions
    
    // MARK: - Address Lookup
    /// Reverse‑geocodes an asset’s location, caching the result so we only ever do it once.
    private let geocoder = CLGeocoder()

    func placemark(for asset: PHAsset) async -> String {
        let id = asset.localIdentifier

        // 1) Cache hit?
        if let cached = imageCacheService.cachedPlacemark(for: id) {
            return cached
        }

        // 2) Build address or fallback
        let address: String
        if let loc = asset.location {
            do {
                let places = try await geocoder.reverseGeocodeLocation(loc)
                let comps = [places.first?.name,
                             places.first?.locality,
                             places.first?.administrativeArea]
                             .compactMap { $0 }
                address = comps.isEmpty ? "Nearby Location"
                                        : comps.joined(separator: ", ")
            } catch {
                address = "Address not found"
            }
        } else {
            address = "No Location Data"
        }

        // 3) Cache & return
        imageCacheService.cachePlacemark(address, for: id)
        return address
    }

    private func calculateDateRange(yearsAgo: Int, calendar: Calendar, today: Date) -> (start: Date, end: Date)? {
        // Extract year, month, day from today
        var components = calendar.dateComponents([.year, .month, .day], from: today)
        
        // Calculate target year
        components.year = (components.year ?? calendar.component(.year, from: today)) - yearsAgo
        
        // Create target date
        guard let targetDate = calendar.date(from: components) else {
            print("❌ Error: Could not calculate target date for \(yearsAgo) years ago.")
            return nil
        }
        
        // Get start of the target day
        let startOfDay = calendar.startOfDay(for: targetDate)
        
        // Calculate end of the target day (typically next day's start)
        guard let endOfDay = calendar.date(
            byAdding: .day,
            value: Constants.daysToAddForDateRangeEnd,
            to: startOfDay
        ) else {
            print("❌ Error: Could not calculate end of day for target date.")
            return nil
        }
        
        return (startOfDay, endOfDay)
    }

    // This function MUST be called from the MainActor (e.g., view's onDisappear)
    func performCleanup() {
        print("🧹 Performing ViewModel cleanup (cancelling tasks and clearing state)...")
        
        // Cancel load tasks
        print("🚫 Cancelling load tasks...")
        activeLoadTasks.values.forEach { $0.cancel() }
        activeLoadTasks.removeAll()
        
        // Cancel grid load tasks
        print("🚫 Cancelling grid load tasks...")
        activeGridLoadTasks.values.forEach { $0.cancel() }
        activeGridLoadTasks.removeAll()
        
        // Cancel thumbnail prefetch tasks
        print("🚫 Cancelling thumbnail prefetch tasks...")
        activePrefetchThumbnailTasks.values.forEach { $0.cancel() }
        activePrefetchThumbnailTasks.removeAll()
        
        // Cancel featured prefetch tasks
        print("🚫 Cancelling featured prefetch tasks...")
        activeFeaturedPrefetchTasks.values.forEach { $0.cancel() }
        activeFeaturedPrefetchTasks.removeAll()
        
        // Cancel background scan task
        print("🚫 Cancelling background year scan task...")
        backgroundYearScanTask?.cancel()
        backgroundYearScanTask = nil
        
        // Clear cached images
        print("🧹 Clearing preloaded featured images during cleanup.")
        preloadedFeaturedImages.removeAll()
        
        print("🧹 ViewModel cleanup complete.")
    }

    // --- DEINIT ---
    deinit { print("🗑️ PhotoViewModel deinit finished."); backgroundYearScanTask?.cancel() } // Keep simple

} // End of PhotoViewModel class

