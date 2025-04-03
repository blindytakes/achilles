import SwiftUI
import Photos
import AVKit // For AVURLAsset

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
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, info in
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

} // End of class PhotoViewModel
