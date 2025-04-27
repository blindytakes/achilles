import SwiftUI
import Photos
import AVKit
import UIKit


// --- State Definition for Each Page/Year ---
enum PageState {
    case idle
    case loading
    case loaded(featured: MediaItem?, grid: [MediaItem]) // Holds prepared data
    case empty
    case error(message: String)
    // Note: No Equatable conformance needed with the updated check below
}

// --- ViewModel ---
@MainActor // Ensure UI updates happen on the main threadlets
class PhotoViewModel: ObservableObject {
    private let service: PhotoLibraryServiceProtocol
    private let selector: FeaturedSelectorServiceProtocol

    
    
    // --- Published Properties for UI ---
    @Published var pageStateByYear: [Int: PageState] = [:] // State for each year (keyed by yearsAgo)
    @Published var availableYearsAgo: [Int] = [] // Sorted list of years with content
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var initialYearScanComplete: Bool = false // Tracks if availableYearsAgo is ready
    @Published var dismissedSplashForYearsAgo: Set<Int> = []
    @Published var gridAnimationDone: Set<Int> = []
    @Published var gridDateAnimationsCompleted: Set<Int> = [] // Use yearsAgo as the key
    @Published var featuredTextAnimationsCompleted: Set<Int> = [] // Track which years have had their featured text animation

    // Add methods to handle animation state
    func shouldAnimate(yearsAgo: Int) -> Bool {
        !featuredTextAnimationsCompleted.contains(yearsAgo)
    }
    
    func markAnimated(yearsAgo: Int) {
        featuredTextAnimationsCompleted.insert(yearsAgo)
    }
    
    func markSplashDismissed(for yearsAgo: Int) {
        dismissedSplashForYearsAgo.insert(yearsAgo)
    }

    // --- Internal Properties ---
    private let imageManager = PHCachingImageManager()
    private var activeLoadTasks: [Int: Task<Void, Never>] = [:] // Track loading tasks per year
    private let maxYearsToScan = 20 // How far back to look for available years initially

    var thumbnailSize = CGSize(width: 250, height: 250) // Used by GridItemView

    // Add new properties for caching
    private var imageCache = NSCache<NSString, UIImage>()
    private var highResCache = NSCache<NSString, UIImage>()
    private var activeRequests: [String: PHImageRequestID] = [:]
    private let maxCacheSize = 50 // Maximum number of full-size images to cache
    private let maxHighResCacheSize = 10 // Maximum number of high-res images to cache

    init(
            service: PhotoLibraryServiceProtocol = PhotoLibraryService(),
            selector: FeaturedSelectorServiceProtocol = FeaturedSelectorService()
        ) {
            self.service = service
            self.selector = selector

            // Configure your caches
            imageCache.countLimit = maxCacheSize
            imageCache.totalCostLimit = 1024 * 1024 * 100  // 100 MB
            highResCache.countLimit = maxHighResCacheSize
            highResCache.totalCostLimit = 1024 * 1024 * 500  // 500 MB

            // Now that everything’s set up, request permissions
            checkAuthorization()
        }

    // --- 1. Check / Request Permissions ---
    func checkAuthorization() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        self.authorizationStatus = status

        switch status {
        case .authorized:
            print("Photo Library access authorized.")
            Task { await findAvailableYears() }
        case .limited:
            print("Photo Library access limited.")
            Task { await findAvailableYears() }
        case .restricted, .denied:
            print("Photo Library access restricted or denied.")
            self.pageStateByYear = [:]
            self.availableYearsAgo = []
            self.initialYearScanComplete = true
        case .notDetermined:
            print("Requesting Photo Library access...")
            Task {
                let requestedStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                await MainActor.run {
                    self.authorizationStatus = requestedStatus
                    if requestedStatus == .authorized || requestedStatus == .limited {
                        Task { await findAvailableYears() }
                    } else {
                        print("Photo Library access denied after request.")
                        self.initialYearScanComplete = true
                    }
                }
            }
        @unknown default:
            print("Unknown Photo Library authorization status.")
            self.initialYearScanComplete = true
        }
    }

    // --- 2. Initial Scan for Years with Content ---
    private func findAvailableYears() async {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            print("Cannot scan for years without photo library access.")
            await MainActor.run {
                self.initialYearScanComplete = true
            }
            return
        }

        print("Starting initial scan for available years...")
        var foundYears: [Int] = []
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()

        for yearsAgoValue in 1...maxYearsToScan {
            guard let targetDateRange = calculateDateRange(yearsAgo: yearsAgoValue, calendar: calendar, today: today) else {
                print("Skipping year \(yearsAgoValue) due to date calculation error.")
                continue
            }

            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", targetDateRange.start as NSDate, targetDateRange.end as NSDate)
            fetchOptions.fetchLimit = 1

            let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
            if fetchResult.count > 0 {
                foundYears.append(yearsAgoValue)
                // Start pre-fetching for this year
                Task {
                    await preFetchPhotosForYear(yearsAgo: yearsAgoValue)
                }
            }
        }

        print("Scan complete. Found years ago with content: \(foundYears)")
        await MainActor.run {
            self.availableYearsAgo = foundYears.sorted()
            self.initialYearScanComplete = true
        }
    }

    private func preFetchPhotosForYear(yearsAgo: Int) async {
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()
        guard let dateRange = calculateDateRange(yearsAgo: yearsAgo, calendar: calendar, today: today) else {
            return
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", dateRange.start as NSDate, dateRange.end as NSDate)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        fetchOptions.fetchLimit = 50 // Limit to 50 photos for pre-fetching

        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        var assetsToCache: [PHAsset] = []
        
        fetchResult.enumerateObjects { (asset, _, _) in
            assetsToCache.append(asset)
        }

        // Start caching the assets with a smaller target size for pre-fetching
        if !assetsToCache.isEmpty {
            let targetSize = CGSize(width: 200, height: 200) // Smaller size for pre-fetching
            imageManager.startCachingImages(for: assetsToCache, targetSize: targetSize, contentMode: .aspectFit, options: nil)
            print("Pre-fetched \(assetsToCache.count) thumbnails for \(yearsAgo) years ago")
        }
    }

    func loadPage(yearsAgo: Int) async {
        // 1) Guard access & avoid duplicate loads
        guard authorizationStatus == .authorized || authorizationStatus == .limited else { return }
        if activeLoadTasks[yearsAgo] != nil { return }

        await MainActor.run {
        activeLoadTasks[yearsAgo] = Task { /* placeholder so we know it’s loading */ }
        }
        
        // 2) Mark the page as loading
        await MainActor.run {
            pageStateByYear[yearsAgo] = .loading
        }

        // 3) Compute the target date
        let targetDate = Calendar.current.date(
            byAdding: .year,
            value: -yearsAgo,
            to: Date()
        )!

        // 4) Kick off the service call
        service.fetchItems(for: targetDate) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let items):
                    if items.isEmpty {
                        self.pageStateByYear[yearsAgo] = .empty
                    } else {
                        let featured = self.selector.pickFeaturedItem(from: items)
                        let grid = Array(items.dropFirst())
                        self.pageStateByYear[yearsAgo] = .loaded(featured: featured, grid: grid)
                    }
                case .failure(let err):
                    self.pageStateByYear[yearsAgo] = .error(message: err.localizedDescription)
                }
                // 5) Clear the “active load” marker
                self.activeLoadTasks[yearsAgo] = nil
            }
        }
    }


    // --- 4. Trigger Pre-fetching for Adjacent Years ---
    func triggerPrefetch(around centerYearsAgo: Int) {
        guard initialYearScanComplete else { return }

        let prevYear = centerYearsAgo + 1
        let nextYear = centerYearsAgo - 1
        let yearsToCheck = [prevYear, nextYear].filter { $0 > 0 }

        print("Triggering prefetch around \(centerYearsAgo). Checking years: \(yearsToCheck)")

        for yearToPrefetch in yearsToCheck {
            if availableYearsAgo.contains(yearToPrefetch) {
                let currentState = pageStateByYear[yearToPrefetch]

                var shouldPrefetch = false
                if currentState == nil { // If no state exists yet
                    shouldPrefetch = true
                } else if case .idle = currentState { // If state is specifically .idle
                    shouldPrefetch = true
                }
                // Optional: Add check for .error if you want retry on prefetch

                if shouldPrefetch {
                    if activeLoadTasks[yearToPrefetch] == nil {
                        print("Prefetching page for \(yearToPrefetch) years ago.")
                        Task {
                            await loadPage(yearsAgo: yearToPrefetch)
                        }
                    }
                }
            }
        }
    }

    // --- 5. Retry Logic (Called by UI) ---
    // UI calls loadPage(yearsAgo:) directly via the retry button.

    // --- 6. Image & Video Loading Functions (Unchanged) ---
    func requestImage(for asset: PHAsset, targetSize: CGSize, completion: @escaping (UIImage?) -> Void) {
        let assetIdentifier = asset.localIdentifier
        let isHighRes = targetSize == PHImageManagerMaximumSize
        
        // Check appropriate cache first
        if let cachedImage = cachedImage(for: assetIdentifier, isHighRes: isHighRes) {
            print("✅ Using cached \(isHighRes ? "high-res" : "thumbnail") image for asset: \(assetIdentifier)")
            completion(cachedImage)
            return
        }
        
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = isHighRes ? .highQualityFormat : .opportunistic
        options.resizeMode = isHighRes ? .none : .fast
        options.isSynchronous = false
        options.version = .current
        
        // Cancel any existing request for this asset
        if let existingRequestID = activeRequests[assetIdentifier] {
            imageManager.cancelImageRequest(existingRequestID)
        }
        
        options.progressHandler = { progress, error, stop, info in
            if let error = error {
                print("❌ Error loading image: \(error.localizedDescription)")
                print("📊 Progress: \(progress)")
                if progress < 1.0 {
                    self.retryImageRequest(for: asset, targetSize: targetSize, completion: completion)
                }
            }
        }
        
        let requestID = imageManager.requestImage(for: asset,
                                                targetSize: targetSize,
                                                contentMode: .aspectFit,
                                                options: options) { [weak self] image, info in
            
            // Remove from active requests
            self?.activeRequests.removeValue(forKey: assetIdentifier)
            
            if let error = info?[PHImageErrorKey] as? Error {
                print("❌ Error loading image: \(error.localizedDescription)")
                self?.retryImageRequest(for: asset, targetSize: targetSize, completion: completion)
                return
            }
            
            if let image = image {
                // Cache the image using the appropriate cache
                self?.cacheImage(image, for: assetIdentifier, isHighRes: isHighRes)
                DispatchQueue.main.async {
                    completion(image)
                }
            } else {
                print("⚠️ Image was nil for asset \(assetIdentifier)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
        
        // Store the request ID
        activeRequests[assetIdentifier] = requestID
    }

    private func retryImageRequest(for asset: PHAsset, targetSize: CGSize, completion: @escaping (UIImage?) -> Void) {
        let assetIdentifier = asset.localIdentifier
        let retryOptions = PHImageRequestOptions()
        retryOptions.isNetworkAccessAllowed = true
        retryOptions.deliveryMode = .highQualityFormat
        retryOptions.resizeMode = .none
        retryOptions.isSynchronous = false
        retryOptions.version = .current
        
        // Cancel existing retry request if any
        if let existingRequestID = activeRequests[assetIdentifier] {
            imageManager.cancelImageRequest(existingRequestID)
        }
        
        let requestID = imageManager.requestImage(for: asset,
                                                targetSize: targetSize,
                                                contentMode: .aspectFit,
                                                options: retryOptions) { [weak self] retryImage, retryInfo in
            guard let self = self else { return }
            
            // Remove from active requests
            self.activeRequests.removeValue(forKey: assetIdentifier)
            
            if let retryImage = retryImage {
                // Cache the retried image using the helper method
                self.cacheImage(retryImage, for: assetIdentifier)
                DispatchQueue.main.async {
                    completion(retryImage)
                }
            } else {
                print("⚠️ Retry failed for asset \(assetIdentifier)")
                if let retryError = retryInfo?[PHImageErrorKey] as? Error {
                    print("❌ Retry error: \(retryError.localizedDescription)")
                }
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
        
        // Store the retry request ID
        activeRequests[assetIdentifier] = requestID
    }

    // Keep internal or change to public if needed elsewhere
    internal func clearImageCache() {
        imageCache.removeAllObjects()
        print("🧹 Cleared image cache due to memory pressure")
    }

    func requestFullImageData(for asset: PHAsset) async -> Data? {
        // Consider replacing this with requestImage(targetSize: PHImageManagerMaximumSize) for memory saving
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .none
            imageManager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
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
                    print("Error requesting AVAsset: \(error)")
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

    // --- 7. Limited Library Picker (Placeholder) ---
    func presentLimitedLibraryPicker() {
        print("Placeholder: Would present limited library picker here.")
        // Needs UI layer integration
    }

    // --- Private Helper Functions ---
    private func calculateDateRange(yearsAgo: Int, calendar: Calendar, today: Date) -> (start: Date, end: Date)? {
        var components = calendar.dateComponents([.year, .month, .day], from: today)
        components.year = (components.year ?? 0) - yearsAgo

        guard let targetDate = calendar.date(from: components) else {
            print("Error: Could not calculate target date for \(yearsAgo) years ago.")
            return nil
        }
        let startOfDay = calendar.startOfDay(for: targetDate)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            print("Error: Could not calculate end of day for target date.")
            return nil
        }
        return (startOfDay, endOfDay)
    }

    // Internal method to check the cache
    internal func cachedImage(for assetIdentifier: String, isHighRes: Bool = false) -> UIImage? {
        if isHighRes {
            if let cached = highResCache.object(forKey: assetIdentifier as NSString) {
                print("✅ Using cached high-res image for asset: \(assetIdentifier)")
                return cached
            }
        } else {
            if let cached = imageCache.object(forKey: assetIdentifier as NSString) {
                print("✅ Using cached thumbnail for asset: \(assetIdentifier)")
                return cached
            }
        }
        return nil
    }
    
    // Internal method to store an image in the cache
    internal func cacheImage(_ image: UIImage, for assetIdentifier: String, isHighRes: Bool = false) {
        // Estimate cost based on image size (pixels * bytes per pixel)
        let cost = Int(image.size.width * image.size.height * image.scale * 4) // Assuming 4 bytes per pixel (RGBA)
        
        if isHighRes {
            // Clear some space if needed
            if highResCache.totalCostLimit < cost {
                highResCache.removeAllObjects()
            }
            highResCache.setObject(image, forKey: assetIdentifier as NSString, cost: cost)
            print("📦 Cached high-res image for asset: \(assetIdentifier), size: \(image.size), cost: \(cost)")
        } else {
            imageCache.setObject(image, forKey: assetIdentifier as NSString, cost: cost)
            print("📦 Cached thumbnail for asset: \(assetIdentifier), size: \(image.size), cost: \(cost)")
        }
    }

}







