import WidgetKit
import SwiftUI

// MARK: - Data Model (Timeline Entry)
struct PhotoEntry: TimelineEntry {
    let date: Date
    let image: UIImage?
    let yearsAgoText: String
    let formattedDate: String
}

// MARK: - Timeline Provider
struct Provider: TimelineProvider {
    typealias Entry = PhotoEntry

    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), image: UIImage(systemName: "photo"), yearsAgoText: "1 Year Ago", formattedDate: "April 5th, 2024")
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> ()) {
        let entry = loadPhotoEntry()
        completion(entry)
    }

    // --- This is the RESTORED getTimeline with carousel logic ---
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.plzwork.Achilles") // Ensure ID is correct

        var entries: [Entry] = []
        let fileManager = FileManager.default
        let now = Date()
        
        // Generate today's date string to use in filenames
        let today = getTodayString()
        
        // Default refresh policy - make sure it refreshes at midnight
        var policy: TimelineReloadPolicy = .after(getMidnightDate())

        if let containerURL = containerURL {
            do {
                // First, check if we need to generate today's content at midnight
                let todayFlagFile = containerURL.appendingPathComponent("today_\(today).flag")
                let needsRefresh = !fileManager.fileExists(atPath: todayFlagFile.path)
                
                if needsRefresh {
                    // We need to trigger a background refresh to get photos for the new day
                    triggerBackgroundPhotoFetch(forDate: today)
                    
                    // Create the flag file to indicate we've initiated refresh for today
                    try? Data().write(to: todayFlagFile, options: .atomic)
                    print("✅ Created flag file and initiated background refresh for \(today)")
                }
                
                let contents = try fileManager.contentsOfDirectory(at: containerURL, includingPropertiesForKeys: nil)
                // Find all files like "featured_DATE.txt" or "featured_INDEX.txt"
                let dateFiles = contents.filter { $0.lastPathComponent.hasPrefix("featured_") && $0.pathExtension == "txt" }
                // Sort them (ensure filenames sort chronologically, e.g., "featured_0", "featured_1" or by date in name)
                let sortedDateFiles = dateFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }

                print("Found \(sortedDateFiles.count) date files for timeline.") // Debug print

                // Load the single featured image (as per original logic)
                let imageURL = containerURL.appendingPathComponent("featured.jpg")
                let image = UIImage(contentsOfFile: imageURL.path)

                // We'll create hourly entries regardless of what we have in the container
                for hour in 0..<24 {
                    let entryDate = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
                    
                    // If the hour is already past, schedule for tomorrow
                    let finalEntryDate = entryDate > now ? entryDate : Calendar.current.date(byAdding: .day, value: 1, to: entryDate) ?? entryDate
                    
                    // Try to get an image for this hour's entry (rotate through available images)
                    var hourImage = image
                    var hourYearsAgoText = "Years Ago"
                    var hourFormattedDate = "Date"
                    
                    // If we have multiple date files, use them for different hours
                    if !sortedDateFiles.isEmpty {
                        let dateIndex = hour % sortedDateFiles.count
                        let dateURL = sortedDateFiles[dateIndex]
                        
                        if let timestampString = try? String(contentsOf: dateURL, encoding: .utf8),
                           let timestamp = TimeInterval(timestampString) {
                            
                            let creationDate = Date(timeIntervalSince1970: timestamp)
                            hourFormattedDate = formatDateNicely(creationDate)
                            
                            let calendar = Calendar.current
                            let creationYear = calendar.component(.year, from: creationDate)
                            let currentYear = calendar.component(.year, from: now)
                            let yearsAgo = currentYear - creationYear
                            hourYearsAgoText = (yearsAgo == 0) ? "This Year" : (yearsAgo == 1 ? "1 Year Ago" : "\(yearsAgo) Years Ago")
                        }
                    }
                    
                    entries.append(Entry(
                        date: finalEntryDate,
                        image: hourImage,
                        yearsAgoText: hourYearsAgoText,
                        formattedDate: hourFormattedDate
                    ))
                    print("Added hourly entry for \(finalEntryDate)")
                }

                // Always ensure we refresh at midnight to get the next day's content
                policy = .after(getMidnightDate())
                print("Timeline policy set to refresh at midnight: \(getMidnightDate())")

            } catch {
                print("❌ Error reading shared container for timeline: \(error)")
            }
        } else {
            print("❌ Could not access App Group container for timeline.")
        }

        // Fallback if no entries were generated from files
        if entries.isEmpty {
            print("Timeline entries list empty, adding single fallback entry.")
            entries.append(loadPhotoEntry(fallback: true))
            // Ensure we still try again at midnight
            policy = .after(getMidnightDate())
        }

        // Sort entries by date to ensure proper timeline order
        entries.sort { $0.date < $1.date }
        
        // Create the final timeline
        let timeline = Timeline(entries: entries, policy: policy)
        completion(timeline)
    }
    
    // Helper to get today's date as a string (YYYY-MM-DD format)
    private func getTodayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    
    // Helper to trigger background fetch of photos without opening the app
    private func triggerBackgroundPhotoFetch(forDate dateString: String) {
        // This would ideally connect to your app's background refresh mechanism
        // For now, we'll create a file that the app can check when it launches
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.plzwork.Achilles") {
            let refreshNeededURL = containerURL.appendingPathComponent("refresh_needed_\(dateString).flag")
            try? Data().write(to: refreshNeededURL, options: .atomic)
            
            // Optional: You could also use UserDefaults in the shared container
            // to communicate with the main app
            if let sharedDefaults = UserDefaults(suiteName: "group.plzwork.Achilles") {
                sharedDefaults.set(true, forKey: "widget_needs_refresh")
                sharedDefaults.set(dateString, forKey: "widget_refresh_date")
            }
            
            print("Flagged for background refresh: \(dateString)")
        }
    }

    // --- Helper Function to Load Data (Simplified single entry load) ---
     private func loadPhotoEntry(fallback: Bool = false) -> Entry {
        let groupIdentifier = "group.plzwork.Achilles" // Your App Group ID
        let defaultImage = UIImage(systemName: "photo.fill") // A fallback SF Symbol
        var loadedImage: UIImage? = nil
        var yearsAgoText = "Some time ago"
        var formattedDate = "Date Unknown"
        let currentDate = Date()

        // Only attempt file loading if not forcing fallback
        if !fallback, let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) {
            let imageURL = containerURL.appendingPathComponent("featured.jpg")
            loadedImage = UIImage(contentsOfFile: imageURL.path) // Simpler loading

            // Assuming only ONE date file for simplicity now: "featured_date.txt"
            let dateURL = containerURL.appendingPathComponent("featured_date.txt")
            // Use explicit encoding
            if let timestampString = try? String(contentsOf: dateURL, encoding: .utf8),
               let timestamp = TimeInterval(timestampString) {

                let creationDate = Date(timeIntervalSince1970: timestamp)
                formattedDate = formatDateNicely(creationDate) // Use date formatting helper

                let calendar = Calendar.current
                let creationYear = calendar.component(.year, from: creationDate)
                let currentYear = calendar.component(.year, from: currentDate)
                let yearsAgo = currentYear - creationYear

                if yearsAgo == 0 {
                    yearsAgoText = "This Year"
                } else {
                    yearsAgoText = yearsAgo == 1 ? "1 Year Ago" : "\(yearsAgo) Years Ago"
                }
            } else {
                 print("❌ Could not load or parse date file.")
            }
        } else if !fallback {
            print("❌ Could not access App Group container.")
        }

        return Entry(
            date: currentDate,
            image: loadedImage ?? defaultImage, // Use loaded image or fallback SF Symbol
            yearsAgoText: yearsAgoText,
            formattedDate: formattedDate
        )
    }


    // --- Date Formatting Helper ---
    private func formatDateNicely(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        let base = formatter.string(from: date)
        let day = Calendar.current.component(.day, from: date)
        let suffix: String
        switch day {
        case 11, 12, 13: suffix = "th"
        default:
            switch day % 10 {
            case 1: suffix = "st"; case 2: suffix = "nd"; case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        let year = Calendar.current.component(.year, from: date)
        return base + suffix + ", \(year)"
    }

    // Helper function to get midnight
    private func getMidnightDate() -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.day = (components.day ?? 0) + 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        
        // Return midnight of next day, fallback to +24h if calendar fails
        return calendar.date(from: components) ?? Date().addingTimeInterval(24 * 60 * 60)
    }
}

// MARK: - SwiftUI View (Final Version)
struct PhotoWidgetEntryView: View {
    var entry: Provider.Entry // Use typealias

    // Vignette properties
    private let vignetteOpacity: Double = 0.6
    private let vignetteStartRadius: CGFloat = 100
    private let vignetteEndRadius: CGFloat = 450

    // Corner radius value
    private let imageCornerRadius: CGFloat = 12 // Adjust as desired

    var body: some View {
        ZStack { // Root ZStack
            // --- Image Layer ---
            if let img = entry.image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity) // Expand frame
                    // *** USE clipShape FOR ROUNDED CORNERS ***
                    .clipShape(RoundedRectangle(cornerRadius: imageCornerRadius))
                    // --- Vignette Overlay ---
                    .overlay(
                        RadialGradient(
                            gradient: Gradient(colors: [.clear, .black.opacity(vignetteOpacity)]),
                            center: .center,
                            startRadius: vignetteStartRadius,
                            endRadius: vignetteEndRadius
                        )
                        .allowsHitTesting(false)
                    )
            } else {
                // --- Fallback Layer ---
                ZStack {
                   Color.gray
                       // Apply same clipping to fallback background
                       .clipShape(RoundedRectangle(cornerRadius: imageCornerRadius))
                   Text("No Image Found")
                       .foregroundColor(.white)
                       .padding()
                }
            }

            // --- Text Overlay Layer (using GeometryReader from original code) ---
            GeometryReader { geometry in
                VStack { // Align content bottom
                    Spacer()
                    VStack(spacing: 0) { // Group text
                        Text(entry.yearsAgoText)
                            .font(.system(size: min(geometry.size.width, geometry.size.height) * 0.12, weight: .semibold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text(entry.formattedDate)
                            .font(.custom("Snell Roundhand", size: min(geometry.size.width, geometry.size.height) * 0.11)) // Cursive
                            .fontWeight(.bold) // Bolder
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    // Original inner padding/bg/corner for text block
                    .padding(.bottom, geometry.size.height * 0.06)
                    .padding(.horizontal, geometry.size.width * 0.05)
                    .background(Color.black.opacity(0.01))
                    .cornerRadius(10)
                }
                .padding(.bottom, geometry.size.height * 0.10) // Original outer padding
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } // End GeometryReader
        } // End Root ZStack
        // --- Final Modifiers ---
        // Removed .ignoresSafeArea() as it didn't fix padding
        .containerBackground(for: .widget) { // Set final background
            Color.clear // Use transparent background
        }
    }
}

// MARK: - Widget Configuration (No @main here)
// Ensure @main is ONLY on your WidgetBundle struct
struct YearsAgoWidget: Widget {
    let kind: String = "YearsAgoWidget" // Your widget kind string

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PhotoWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Years Ago Photo") // Your widget display name
        .description("Shows a memory from the past.")
        .supportedFamilies([.systemLarge])
    }
}

