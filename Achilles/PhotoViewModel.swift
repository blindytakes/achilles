import SwiftUI
import Photos
import AVKit // For AVURLAsset
import WidgetKit

// --- Data Model (Assuming this remains the same) ---
struct MediaItem: Identifiable, Hashable {
    let id: String // Use asset local identifier
    let asset: PHAsset
}

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

    // --- Published Properties for UI ---
    @Published var pageStateByYear: [Int: PageState] = [:] // State for each year (keyed by yearsAgo)
    @Published var availableYearsAgo: [Int] = [] // Sorted list of years with content
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var initialYearScanComplete: Bool = false // Tracks if availableYearsAgo is ready

    // --- Internal Properties ---
    private var mediaByYear: [Int: [MediaItem]] = [:] // Cache for all items per year
    private let imageManager = PHCachingImageManager()
    private var activeLoadTasks: [Int: Task<Void, Never>] = [:] // Track loading tasks per year
    private let maxYearsToScan = 20 // How far back to look for available years initially

    var thumbnailSize = CGSize(width: 250, height: 250) // Used by GridItemView

    // --- Initialization ---
    init() {
        checkAuthorization()
        checkWidgetRefreshFlags() // Check if widget needs new photos
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
            }
        }

        print("Scan complete. Found years ago with content: \(foundYears)")
        await MainActor.run {
            self.availableYearsAgo = foundYears.sorted()
            self.initialYearScanComplete = true
            // *** Initial Load Trigger REMOVED from here ***
            // Let the YearPageView.onAppear handle the first load.
        }
    }

    // --- 3. Load Content for a Specific Year's Page ---
    func loadPage(yearsAgo: Int) async {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            print("Cannot load page \(yearsAgo) without photo library access.")
            return
        }

        if activeLoadTasks[yearsAgo] != nil {
            print("Already loading page for \(yearsAgo) years ago.")
            return
        }
        // Optional: Uncomment return if you don't want explicit reload/retry on loaded state
        // if case .loaded = pageStateByYear[yearsAgo] {
        //    print("Page for \(yearsAgo) years ago already loaded.")
        //    return
        // }

        let loadTask = Task {
            // Always switch to main actor for state updates
            await MainActor.run {
                pageStateByYear[yearsAgo] = .loading
                print("Loading page for \(yearsAgo) years ago...")
            }

            let calendar = Calendar(identifier: .gregorian)
            let today = Date()
            guard let dateRange = calculateDateRange(yearsAgo: yearsAgo, calendar: calendar, today: today) else {
                await MainActor.run {
                    pageStateByYear[yearsAgo] = .error(message: "Failed to calculate date range.")
                    activeLoadTasks[yearsAgo] = nil // Clear task before returning
                }
                return
            }

            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", dateRange.start as NSDate, dateRange.end as NSDate)
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

            let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
            var fetchedItems: [MediaItem] = []
            if fetchResult.count > 0 {
                fetchResult.enumerateObjects { (asset, _, _) in
                    fetchedItems.append(MediaItem(id: asset.localIdentifier, asset: asset))
                }
            }

            // Update state back on main actor
            await MainActor.run {
                if fetchedItems.isEmpty {
                    print("Page loaded for \(yearsAgo) years ago: Empty")
                    pageStateByYear[yearsAgo] = .empty
                    mediaByYear[yearsAgo] = []
                } else {
                    print("Page loaded for \(yearsAgo) years ago: \(fetchedItems.count) items")
                    mediaByYear[yearsAgo] = fetchedItems
                    let featured = fetchedItems.first
                    let gridItems = Array(fetchedItems.dropFirst())
                    pageStateByYear[yearsAgo] = .loaded(featured: featured, grid: gridItems)
                }
                activeLoadTasks[yearsAgo] = nil // Clear task on completion
            }
        } // End of Task

        await MainActor.run {
            activeLoadTasks[yearsAgo] = loadTask // Store task handle
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
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat  // High quality for better display
        options.resizeMode = .exact
        options.isSynchronous = false  // Async loading for better UI performance
        
        // Use aspectFit to show the entire image without cropping
        imageManager.requestImage(for: asset,
                                targetSize: targetSize,
                                contentMode: .aspectFit,
                                options: options) { image, info in
            
            // Check if this is a degraded image (preview while loading)
            if let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool, isDegraded {
                // Still show degraded images initially
            }
            
            completion(image)
        }
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

    // --- Check for widget refresh flags ---
    private func checkWidgetRefreshFlags() {
        Task {
            guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.plzwork.Achilles") else {
                return
            }
            
            let fileManager = FileManager.default
            
            do {
                // Look for any refresh_needed files
                let contents = try fileManager.contentsOfDirectory(at: containerURL, includingPropertiesForKeys: nil)
                let refreshFlags = contents.filter { $0.lastPathComponent.hasPrefix("refresh_needed_") && $0.pathExtension == "flag" }
                
                for flagURL in refreshFlags {
                    // Extract date from filename (refresh_needed_YYYY-MM-DD.flag)
                    let filename = flagURL.deletingPathExtension().lastPathComponent
                    if let dateString = filename.components(separatedBy: "refresh_needed_").last,
                       !dateString.isEmpty {
                        
                        print("Processing widget refresh request for date: \(dateString)")
                        
                        // Process this date - load photos for this day
                        await updatePhotosForWidget(dateString: dateString)
                        
                        // Delete the flag file after processing
                        try? fileManager.removeItem(at: flagURL)
                    }
                }
                
                // Also check UserDefaults
                if let sharedDefaults = UserDefaults(suiteName: "group.plzwork.Achilles"),
                   sharedDefaults.bool(forKey: "widget_needs_refresh"),
                   let dateString = sharedDefaults.string(forKey: "widget_refresh_date") {
                    
                    print("Processing widget refresh from UserDefaults for date: \(dateString)")
                    await updatePhotosForWidget(dateString: dateString)
                    
                    // Clear the flags
                    sharedDefaults.set(false, forKey: "widget_needs_refresh")
                }
            } catch {
                print("Error checking widget refresh flags: \(error)")
            }
        }
    }
    
    // Update photos for the widget for a specific date
    private func updatePhotosForWidget(dateString: String) async {
        // Parse the date string
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else {
            print("Invalid date format for widget refresh: \(dateString)")
            return
        }
        
        // Find photos from years ago on this date
        // This would use the same logic as your existing year-ago photo finder
        // For each available year in the past:
        for yearsAgo in 1...10 { // Check up to 10 years back
            // Logic to find photos from 'yearsAgo' on the month/day of 'date'
            if let item = await fetchFeaturedMediaForYearsAgo(yearsAgo, fromDate: date) {
                // Save this to the container for the widget in a year-specific file
                await saveFeaturedPhotoToContainer(item: item, yearsAgo: yearsAgo, dateString: dateString)
            }
        }
        
        // After updating, reload the widget
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    // Fetch a featured item for years ago from a specific date
    private func fetchFeaturedMediaForYearsAgo(_ yearsAgo: Int, fromDate date: Date) async -> MediaItem? {
        // This would be similar to your existing logic to find photos from years ago
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        
        // Create a date from 'yearsAgo' years ago with same month/day
        var pastComponents = components
        pastComponents.year = (components.year ?? 0) - yearsAgo
        
        guard let pastDate = calendar.date(from: pastComponents) else {
            return nil
        }
        
        // Create start and end of that day
        let startOfDay = calendar.startOfDay(for: pastDate)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return nil
        }
        
        // Find photos within that day range
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate < %@",
            startOfDay as NSDate,
            endOfDay as NSDate
        )
        
        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        if fetchResult.count > 0 {
            // Return the first item
            let asset = fetchResult.object(at: 0)
            return MediaItem(id: asset.localIdentifier, asset: asset)
        }
        
        return nil
    }
    
    // Save a featured photo to the container for the widget
    private func saveFeaturedPhotoToContainer(item: MediaItem, yearsAgo: Int, dateString: String) async {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.plzwork.Achilles") else {
            return
        }
        
        // Request the image at a size suitable for the widget
        let targetSize = CGSize(width: 800, height: 800)
        
        // Request image for the asset
        let imageManager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isSynchronous = true
        
        var savedImage: UIImage?
        imageManager.requestImage(
            for: item.asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            savedImage = image
        }
        
        guard let image = savedImage, let data = image.jpegData(compressionQuality: 0.8) else {
            return
        }
        
        // Save the image for this year-ago period
        let imageFileName = "featured_\(yearsAgo)_\(dateString).jpg"
        let imageURL = containerURL.appendingPathComponent(imageFileName)
        
        do {
            try data.write(to: imageURL)
            
            // Save the creation date timestamp for the widget
            if let creationDate = item.asset.creationDate {
                let timestamp = creationDate.timeIntervalSince1970
                let dateFileName = "featured_\(yearsAgo)_\(dateString).txt"
                let dateFileURL = containerURL.appendingPathComponent(dateFileName)
                try "\(timestamp)".write(to: dateFileURL, atomically: true, encoding: .utf8)
                
                // Also update the main featured image for the widget
                if yearsAgo == 1 {
                    let mainImageURL = containerURL.appendingPathComponent("featured.jpg")
                    try data.write(to: mainImageURL)
                    
                    let mainDateFileURL = containerURL.appendingPathComponent("featured_date.txt")
                    try "\(timestamp)".write(to: mainDateFileURL, atomically: true, encoding: .utf8)
                }
                
                print("✅ Saved widget photo for \(yearsAgo) years ago on \(dateString)")
            }
        } catch {
            print("❌ Error saving widget photo: \(error)")
        }
    }

} // End of class PhotoViewModel


