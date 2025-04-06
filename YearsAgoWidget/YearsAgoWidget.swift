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
            // Default refresh policy if something goes wrong
            var policy: TimelineReloadPolicy = .after(Calendar.current.date(byAdding: .hour, value: 1, to: now)!)

            if let containerURL = containerURL {
                do {
                    let contents = try fileManager.contentsOfDirectory(at: containerURL, includingPropertiesForKeys: nil)
                    // Find all files like "featured_DATE.txt" or "featured_INDEX.txt"
                    let dateFiles = contents.filter { $0.lastPathComponent.hasPrefix("featured_") && $0.pathExtension == "txt" }
                    // Sort them (ensure filenames sort chronologically, e.g., "featured_0", "featured_1" or by date in name)
                    let sortedDateFiles = dateFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }

                    print("Found \(sortedDateFiles.count) date files for timeline.") // Debug print

                    // Load the single featured image (as per original logic)
                    let imageURL = containerURL.appendingPathComponent("featured.jpg")
                    let image = UIImage(contentsOfFile: imageURL.path)

                    for (index, dateURL) in sortedDateFiles.enumerated() {
                        // Read timestamp from each date file
                        if let timestampString = try? String(contentsOf: dateURL, encoding: .utf8), // Use explicit encoding
                           let timestamp = TimeInterval(timestampString) {

                            let creationDate = Date(timeIntervalSince1970: timestamp)
                            let formattedDate = formatDateNicely(creationDate) // Use helper

                            let calendar = Calendar.current
                            let creationYear = calendar.component(.year, from: creationDate)
                            let currentYear = calendar.component(.year, from: now)
                            let yearsAgo = currentYear - creationYear
                            let yearsAgoText: String = (yearsAgo == 0) ? "This Year" : (yearsAgo == 1 ? "1 Year Ago" : "\(yearsAgo) Years Ago")

                            // Schedule entry - advance 1 hour for each item in the sorted list
                            let entryDate = Calendar.current.date(byAdding: .hour, value: index, to: now)! // Force unwrap okay here as adding hours should succeed

                            entries.append(Entry(
                                date: entryDate,
                                image: image, // Use the same image for all entries
                                yearsAgoText: yearsAgoText,
                                formattedDate: formattedDate
                            ))
                            print("Added entry for \(dateURL.lastPathComponent) at \(entryDate)") // Debug print
                        } else {
                             print("❌ Could not read or parse timestamp from \(dateURL.lastPathComponent)")
                        }
                    } // End loop

                    // Set the refresh policy based on the last entry's date
                    if let lastDate = entries.last?.date {
                         let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: lastDate)!
                         policy = .after(nextRefresh)
                         print("Timeline policy set to refresh after: \(nextRefresh)") // Debug print
                    } else {
                        print("No entries generated, default hourly refresh policy used.")
                    }

                } catch {
                    print("❌ Error reading shared container for timeline: \(error)")
                }
            } else {
                 print("❌ Could not access App Group container for timeline.")
            }

            // Fallback if no entries were generated from files
            if entries.isEmpty {
                print("Timeline entries list empty, adding single fallback entry.")
                entries.append(loadPhotoEntry(fallback: true)) // Use fallback load function
                 // Keep default hourly refresh if list was empty
            }

            // Create the final timeline
            let timeline = Timeline(entries: entries, policy: policy)
            completion(timeline)
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
