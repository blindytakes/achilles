import SwiftUI
import Photos
import AVKit
import UIKit

@MainActor // Ensure UI updates happen on the main thread
class PhotoViewModel: ObservableObject {

    // MARK: - Nested Constants
    private struct Constants {
        // Configuration
        static let maxYearsToScanInitial: Int = 20 // How far back to look initially
        static let yearCheckFetchLimit: Int = 1 // Fetch limit when checking if year has content
        static let prefetchLimitPerYear: Int = 50 // Max assets to prefetch thumbnails for

        // Image Sizes
        static let defaultThumbnailSize = CGSize(width: 250, height: 250)
        static let prefetchThumbnailSize = CGSize(width: 200, height: 200)
        // Note: PHImageManagerMaximumSize is a system constant, no need to redefine

        // Caching
        static let imageCacheCountLimit: Int = 50
        static let imageCacheMaxCostMB: Int = 100 // In Megabytes
        static let highResCacheCountLimit: Int = 10
        static let highResCacheMaxCostMB: Int = 500 // In Megabytes
        static let bytesPerMegabyte: Int = 1024 * 1024
        static let assumedBytesPerPixel: Int = 4 // For RGBA cost estimation

        // Date Calculations
        static let daysToAddForDateRangeEnd: Int = 1

        // Other Logic
        static let fullProgress: Double = 1.0
    }

    // MARK: - Dependencies
    private let service: PhotoLibraryServiceProtocol
    private let selector: FeaturedSelectorServiceProtocol
    private let imageManager = PHCachingImageManager()

    // MARK: - Published Properties for UI
    @Published var pageStateByYear: [Int: PageState] = [:] // State for each year (keyed by yearsAgo)
    @Published var availableYearsAgo: [Int] = [] // Sorted list of years with content
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var initialYearScanComplete: Bool = false // Tracks if availableYearsAgo is ready
    @Published var dismissedSplashForYearsAgo: Set<Int> = []
    @Published var gridAnimationDone: Set<Int> = []
    @Published var gridDateAnimationsCompleted: Set<Int> = [] // Use yearsAgo as the key
    @Published var featuredTextAnimationsCompleted: Set<Int> = [] // Track which years have had their featured text animation
    @Published var featuredImageAnimationsCompleted: Set<Int> = [] // Track image effects animation

    // MARK: - Internal Properties
    private var activeLoadTasks: [Int: Task<Void, Never>] = [:] // Track loading tasks per year
    var thumbnailSize = Constants.defaultThumbnailSize // Use constant - Used by GridItemView

    // Caching Properties
    private var imageCache = NSCache<NSString, UIImage>()
    private var highResCache = NSCache<NSString, UIImage>()
    private var activeRequests: [String: PHImageRequestID] = [:]

    // How far back to look for available years initially
    private let maxYearsToScan = Constants.maxYearsToScanInitial


    // MARK: - Initialization
    init(
        service: PhotoLibraryServiceProtocol = PhotoLibraryService(),
        selector: FeaturedSelectorServiceProtocol = FeaturedSelectorService()
    ) {
        self.service = service
        self.selector = selector

        // Configure caches using constants
        imageCache.countLimit = Constants.imageCacheCountLimit
        imageCache.totalCostLimit = Constants.imageCacheMaxCostMB * Constants.bytesPerMegabyte
        highResCache.countLimit = Constants.highResCacheCountLimit
        highResCache.totalCostLimit = Constants.highResCacheMaxCostMB * Constants.bytesPerMegabyte

        // Request permissions after setup
        checkAuthorization()
    }

    // MARK: - Animation State Handling
    // --- Methods for Text Animation State ---
    func shouldAnimate(yearsAgo: Int) -> Bool {
        !featuredTextAnimationsCompleted.contains(yearsAgo)
    }
    func markAnimated(yearsAgo: Int) {
        featuredTextAnimationsCompleted.insert(yearsAgo)
        print("✍️ Marked TEXT animation done for \(yearsAgo)")
    }

    // --- Methods for Image Animation State ---
    func shouldAnimateImageEffects(yearsAgo: Int) -> Bool {
        !featuredImageAnimationsCompleted.contains(yearsAgo)
    }
    func markImageEffectsAnimated(yearsAgo: Int) {
        featuredImageAnimationsCompleted.insert(yearsAgo)
        print("🖼️ Marked IMAGE effects animation done for \(yearsAgo)")
    }

    // --- Method for Splash Dismissal ---
    func markSplashDismissed(for yearsAgo: Int) {
        dismissedSplashForYearsAgo.insert(yearsAgo)
    }


    // MARK: - Authorization Handling
    func checkAuthorization() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        self.authorizationStatus = status

        switch status {
        case .authorized, .limited:
            print("Photo Library access status: \(status)")
            Task { await findAvailableYears() }
        case .restricted, .denied:
            print("Photo Library access restricted or denied.")
            self.pageStateByYear = [:]
            self.availableYearsAgo = []
            self.initialYearScanComplete = true
        case .notDetermined:
            print("Requesting Photo Library access...")
            requestAuthorization()
        @unknown default:
            print("Unknown Photo Library authorization status.")
            self.initialYearScanComplete = true
        }
    }

    private func requestAuthorization() {
        Task {
            let requestedStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            // Switch back to main thread to update published properties
            await MainActor.run {
                self.authorizationStatus = requestedStatus
                if requestedStatus == .authorized || requestedStatus == .limited {
                    print("Photo Library access granted: \(requestedStatus)")
                    Task { await findAvailableYears() }
                } else {
                    print("Photo Library access denied after request.")
                    self.initialYearScanComplete = true
                }
            }
        }
    }

    // MARK: - Content Loading & Prefetching
    // Step 2: Find years with content
    private func findAvailableYears() async {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            print("Cannot scan for years without photo library access.")
            await MainActor.run { self.initialYearScanComplete = true }
            return
        }

        print("Starting initial scan for available years (up to \(maxYearsToScan) years ago)...")
        var foundYears: [Int] = []
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()

        // Use constant for loop range
        for yearsAgoValue in 1...maxYearsToScan {
            guard let targetDateRange = calculateDateRange(yearsAgo: yearsAgoValue, calendar: calendar, today: today) else {
                print("Skipping year \(yearsAgoValue) due to date calculation error.")
                continue
            }

            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", targetDateRange.start as NSDate, targetDateRange.end as NSDate)
            // Limit fetch to 1 just to check existence, use constant
            fetchOptions.fetchLimit = Constants.yearCheckFetchLimit

            let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
            if fetchResult.count > 0 {
                foundYears.append(yearsAgoValue)
                // Start pre-fetching thumbnails for this year in the background
                Task.detached(priority: .background) {
                    await self.preFetchPhotosForYear(yearsAgo: yearsAgoValue)
                }
            }
        }

        print("Scan complete. Found years ago with content: \(foundYears)")
        // Update published properties on main thread
        await MainActor.run {
            self.availableYearsAgo = foundYears.sorted()
            self.initialYearScanComplete = true
        }
    }

    // Prefetch initial thumbnails for a given year
    private func preFetchPhotosForYear(yearsAgo: Int) async {
        print("⚡️ Starting prefetch for \(yearsAgo) years ago...")
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()
        guard let dateRange = calculateDateRange(yearsAgo: yearsAgo, calendar: calendar, today: today) else {
            print("⚡️ Prefetch skipped for \(yearsAgo) - date range error.")
            return
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", dateRange.start as NSDate, dateRange.end as NSDate)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        // Use constant for prefetch limit
        fetchOptions.fetchLimit = Constants.prefetchLimitPerYear

        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        guard fetchResult.count > 0 else {
             print("⚡️ No assets found to prefetch for \(yearsAgo) years ago.")
             return
         }

        var assetsToCache: [PHAsset] = []
        fetchResult.enumerateObjects { (asset, _, _) in
            assetsToCache.append(asset)
        }

        // Start caching the assets with prefetch size
        print("⚡️ Requesting caching for \(assetsToCache.count) thumbnails for \(yearsAgo) years ago.")
        imageManager.startCachingImages(
            for: assetsToCache,
            targetSize: Constants.prefetchThumbnailSize, // Use constant
            contentMode: .aspectFit,
            options: nil // Use default options for caching
        )
    }

    // Load full page data for a specific year
    func loadPage(yearsAgo: Int) async {
        // Check authorization and existing tasks
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            print("🚫 Cannot load page \(yearsAgo) - authorization denied.")
            return
        }
        if activeLoadTasks[yearsAgo] != nil {
            print("⏳ Load already in progress for page \(yearsAgo).")
            return
        }

        // Mark as loading
        await MainActor.run {
            // Add placeholder task to prevent duplicate loads
            activeLoadTasks[yearsAgo] = Task { /* Non-functional task as marker */ }
            pageStateByYear[yearsAgo] = .loading
        }
        print("⬆️ Loading page for \(yearsAgo) years ago...")

        // Get target date
        guard let targetDate = Calendar.current.date(byAdding: .year, value: -yearsAgo, to: Date()) else {
             print("❌ Error calculating target date for \(yearsAgo) years ago.")
             await MainActor.run {
                 pageStateByYear[yearsAgo] = .error(message: "Internal date calculation error.")
                 activeLoadTasks[yearsAgo] = nil
             }
             return
         }

        // Fetch items using the service
        service.fetchItems(for: targetDate) { [weak self] result in
            // Ensure UI updates happen on the main thread
            DispatchQueue.main.async {
                guard let self = self else { return }

                switch result {
                case .success(let items):
                    if items.isEmpty {
                        print("✅ Load complete for \(yearsAgo) - Empty.")
                        self.pageStateByYear[yearsAgo] = .empty
                    } else {
                        print("✅ Load complete for \(yearsAgo) - Found \(items.count) items.")
                        // Use selector service to pick featured item
                        let featured = self.selector.pickFeaturedItem(from: items)
                        // Consider different logic for grid items if needed
                        // E.g., remove featured item if it exists
                        let grid = items.filter { $0.id != featured?.id }
                        self.pageStateByYear[yearsAgo] = .loaded(featured: featured, grid: grid)
                    }
                case .failure(let error):
                    print("❌ Load failed for \(yearsAgo): \(error.localizedDescription)")
                    self.pageStateByYear[yearsAgo] = .error(message: error.localizedDescription)
                }
                // Clear the active load marker regardless of outcome
                self.activeLoadTasks[yearsAgo] = nil
            }
        }
    }

    // Trigger pre-fetching for adjacent years
    func triggerPrefetch(around centerYearsAgo: Int) {
        guard initialYearScanComplete else { return }

        let prevYear = centerYearsAgo + 1
        let nextYear = centerYearsAgo - 1
        // Filter out years less than 1
        let yearsToCheck = [prevYear, nextYear].filter { $0 > 0 }

        print("⚡️ Triggering prefetch check around \(centerYearsAgo). Checking: \(yearsToCheck)")

        for yearToPrefetch in yearsToCheck {
            // Only prefetch if the year exists and isn't already loaded/loading/error
            if availableYearsAgo.contains(yearToPrefetch) {
                let currentState = pageStateByYear[yearToPrefetch] ?? .idle
                if case .idle = currentState { // Only prefetch if idle
                    if activeLoadTasks[yearToPrefetch] == nil {
                        print("⚡️ Prefetching page for \(yearToPrefetch) years ago.")
                        Task {
                            await loadPage(yearsAgo: yearToPrefetch)
                        }
                    } else {
                         print("⚡️ Prefetch skipped for \(yearToPrefetch) - already loading.")
                     }
                }
            }
        }
    }


    // MARK: - Image & Video Fetching
    func requestImage(for asset: PHAsset, targetSize: CGSize, completion: @escaping (UIImage?) -> Void) {
        let assetIdentifier = asset.localIdentifier
        let isHighRes = targetSize == PHImageManagerMaximumSize

        // Check appropriate cache first
        if let cachedImage = cachedImage(for: assetIdentifier, isHighRes: isHighRes) {
            print("✅ Using cached \(isHighRes ? "high-res" : "thumbnail") image for asset: \(assetIdentifier)")
            completion(cachedImage)
            return
        }

        print("⬆️ Requesting \(isHighRes ? "high-res" : "thumbnail") image for asset: \(assetIdentifier)")
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = isHighRes ? .highQualityFormat : .opportunistic
        options.resizeMode = isHighRes ? .none : .fast // Use fast for thumbnails
        options.isSynchronous = false // Never block the main thread
        options.version = .current

        // Cancel any existing request for this specific asset identifier
         cancelActiveRequest(for: assetIdentifier)

        // Progress Handler
        options.progressHandler = { [weak self] progress, error, stop, info in
             // Ensure self still exists
             guard let self = self else { return }

             if let error = error {
                 print("❌ Image loading error (progress): \(error.localizedDescription) for \(assetIdentifier)")
                 print("📊 Progress: \(progress)")
                 // Only retry on recoverable errors and if progress is low?
                 // Consider more nuanced error checking if necessary.
                 // Use constant for progress check
                 if progress < Constants.fullProgress {
                     print("🔄 Retrying image request due to progress error for \(assetIdentifier)")
                     self.retryImageRequest(for: asset, targetSize: targetSize, completion: completion)
                 }
                 // Stop the current request if retrying
                 stop.pointee = true
             }
         }

        // Request the image
        let requestID = imageManager.requestImage(
            for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options
        ) { [weak self] image, info in
            // Ensure self exists, clear active request
            guard let self = self else { return }
             // Safely remove request ID only if it matches the completed one
             if self.activeRequests[assetIdentifier] == info?[PHImageResultRequestIDKey] as? PHImageRequestID {
                  self.activeRequests.removeValue(forKey: assetIdentifier)
             }


             // Check for explicit cancellation
             let isCancelled = info?[PHImageCancelledKey] as? Bool ?? false
             if isCancelled {
                 print("🚫 Image request cancelled for \(assetIdentifier).")
                 completion(nil) // Ensure completion handler is called
                 return
             }

            // Check for request errors
            if let error = info?[PHImageErrorKey] as? Error {
                print("❌ Image loading error (completion): \(error.localizedDescription) for \(assetIdentifier)")
                 // Don't retry automatically from completion, maybe rely on progress handler retry
                completion(nil)
                return
            }

            // Process the result image
            if let image = image {
                print("✅ Image loaded successfully for \(assetIdentifier)")
                // Cache the loaded image
                self.cacheImage(image, for: assetIdentifier, isHighRes: isHighRes)
                // Call completion handler (ensure it's on main thread if needed by UI)
                DispatchQueue.main.async { completion(image) }
            } else {
                // Image is nil, but no error? Should ideally not happen with non-sync requests
                // unless cancelled before delivery or error occurred but wasn't caught above.
                print("⚠️ Image was nil, but no error reported for asset \(assetIdentifier)")
                 DispatchQueue.main.async { completion(nil) }
            }
        }

        // Store the request ID to allow cancellation
        activeRequests[assetIdentifier] = requestID
        print("⏳ Stored request ID \(requestID) for asset \(assetIdentifier)")
    }

    // Specific retry logic (called from progress handler usually)
    private func retryImageRequest(for asset: PHAsset, targetSize: CGSize, completion: @escaping (UIImage?) -> Void) {
        print("🔄 Executing retry logic for asset \(asset.localIdentifier)")
        let assetIdentifier = asset.localIdentifier
        let isHighRes = targetSize == PHImageManagerMaximumSize // Recalculate for context

        // Use high quality options for retry attempt
        let retryOptions = PHImageRequestOptions()
        retryOptions.isNetworkAccessAllowed = true
        retryOptions.deliveryMode = .highQualityFormat // Force high quality
        retryOptions.resizeMode = .none // Ensure exact size or full quality
        retryOptions.isSynchronous = false
        retryOptions.version = .current

        // Cancel previous request for this asset before retrying
        cancelActiveRequest(for: assetIdentifier)

        let requestID = imageManager.requestImage(
            for: asset, targetSize: targetSize, contentMode: .aspectFit, options: retryOptions
        ) { [weak self] retryImage, retryInfo in
            guard let self = self else { return }
            // Safely remove request ID only if it matches the completed one
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

            // Handle retry error
            if let retryError = retryInfo?[PHImageErrorKey] as? Error {
                print("❌❌ Retry failed for asset \(assetIdentifier): \(retryError.localizedDescription)")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Process retry image
            if let retryImage = retryImage {
                print("✅✅ Retry successful for asset \(assetIdentifier)")
                self.cacheImage(retryImage, for: assetIdentifier, isHighRes: isHighRes)
                DispatchQueue.main.async { completion(retryImage) }
            } else {
                print("⚠️⚠️ Retry resulted in nil image for asset \(assetIdentifier)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
        // Store the new request ID
        activeRequests[assetIdentifier] = requestID
        print("⏳ Stored retry request ID \(requestID) for asset \(assetIdentifier)")
    }

    // Helper to cancel active request for an asset
    private func cancelActiveRequest(for assetIdentifier: String) {
        if let existingRequestID = activeRequests[assetIdentifier] {
             print("🚫 Cancelling existing request \(existingRequestID) for asset \(assetIdentifier)")
             imageManager.cancelImageRequest(existingRequestID)
             activeRequests.removeValue(forKey: assetIdentifier) // Remove immediately after cancelling
        }
    }

    // Method to clear thumbnail cache (e.g., on memory warning)
    internal func clearImageCache() {
        print("🧹 Clearing image caches...")
        imageCache.removeAllObjects()
        highResCache.removeAllObjects() // Clear high-res cache too
        print("🧹 Image caches cleared.")
    }

    // Fetch full image data (used for sharing)
    func requestFullImageData(for asset: PHAsset) async -> Data? {
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .none
            options.isSynchronous = false // Asynchronous best practice

            print("⬆️ Requesting full image data for sharing asset \(asset.localIdentifier)")
            imageManager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                 if let error = info?[PHImageErrorKey] as? Error {
                     print("❌ Error fetching full image data: \(error.localizedDescription)")
                     continuation.resume(returning: nil)
                 } else if let data = data {
                    print("✅ Full image data fetched for \(asset.localIdentifier)")
                    continuation.resume(returning: data)
                 } else {
                     print("⚠️ Full image data was nil for \(asset.localIdentifier)")
                     continuation.resume(returning: nil)
                 }
            }
        }
    }

    // Fetch video URL (used for player and sharing)
    func requestVideoURL(for asset: PHAsset) async -> URL? {
        guard asset.mediaType == .video else { return nil }

        return await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.version = .current
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .automatic // Let system decide best delivery

             print("⬆️ Requesting AVAsset for video \(asset.localIdentifier)")
            imageManager.requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    print("❌ Error requesting AVAsset for \(asset.localIdentifier): \(error)")
                    continuation.resume(returning: nil)
                    return
                }
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

    // MARK: - Limited Library Handling
    // Placeholder for triggering the limited library picker UI flow
    func presentLimitedLibraryPicker() {
        print("⚠️ Placeholder: Would present limited library picker here.")
        // Implementation requires UIKit interaction, likely via a Coordinator or UIViewControllerRepresentable
    }

    // MARK: - Private Helper Functions
    // Calculate date range for a specific "years ago" value
    private func calculateDateRange(yearsAgo: Int, calendar: Calendar, today: Date) -> (start: Date, end: Date)? {
        var components = calendar.dateComponents([.year, .month, .day], from: today)
        // Adjust year component
        components.year = (components.year ?? calendar.component(.year, from: today)) - yearsAgo

        guard let targetDate = calendar.date(from: components) else {
            print("❌ Error: Could not calculate target date for \(yearsAgo) years ago.")
            return nil
        }
        let startOfDay = calendar.startOfDay(for: targetDate)
        // Use constant for day calculation
        guard let endOfDay = calendar.date(byAdding: .day, value: Constants.daysToAddForDateRangeEnd, to: startOfDay) else {
            print("❌ Error: Could not calculate end of day for target date.")
            return nil
        }
        return (startOfDay, endOfDay)
    }

    // Check appropriate cache for an image
    // Changed to public as ItemDisplayView uses it now
    public func cachedImage(for assetIdentifier: String, isHighRes: Bool = false) -> UIImage? {
        let cache = isHighRes ? highResCache : imageCache
        let cacheName = isHighRes ? "high-res" : "thumbnail"

        if let cached = cache.object(forKey: assetIdentifier as NSString) {
            print("✅ Using cached \(cacheName) image for asset: \(assetIdentifier)")
            return cached
        }
        return nil
    }

    // Store an image in the appropriate cache with cost calculation
    // Changed to public as ItemDisplayView uses it now
    public func cacheImage(_ image: UIImage, for assetIdentifier: String, isHighRes: Bool = false) {
        // Estimate cost based on image dimensions, scale, and assumed bytes per pixel
        let cost = Int(image.size.width * image.size.height * image.scale * CGFloat(Constants.assumedBytesPerPixel)) // Use constant

        if isHighRes {
            // Basic checks before adding to cache (NSCache handles actual limits)
            if highResCache.totalCostLimit > 0 && highResCache.totalCostLimit < cost {
                 print("⚠️ High-res cache limit potentially exceeded by new image cost (\(cost) vs limit \(highResCache.totalCostLimit)). Cache might be cleared.")
            }
            highResCache.setObject(image, forKey: assetIdentifier as NSString, cost: cost)
            print("📦 Cached high-res image for asset: \(assetIdentifier), size: \(image.size), cost: \(cost)")
        } else {
             if imageCache.totalCostLimit > 0 && imageCache.totalCostLimit < cost {
                 print("⚠️ Thumbnail cache limit potentially exceeded by new image cost (\(cost) vs limit \(imageCache.totalCostLimit)). Cache might be cleared.")
             }
            imageCache.setObject(image, forKey: assetIdentifier as NSString, cost: cost)
            print("📦 Cached thumbnail for asset: \(assetIdentifier), size: \(image.size), cost: \(cost)")
        }
    }

} // End of class PhotoViewModel

// Removed flawed NSCache currentCount extension
