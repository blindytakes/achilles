import WidgetKit
import SwiftUI

struct PhotoEntry: TimelineEntry {
    let date: Date
    let image: UIImage?
    let yearsAgoText: String
    let formattedDate: String
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> PhotoEntry {
        PhotoEntry(date: Date(), image: nil, yearsAgoText: "4 Years Ago", formattedDate: "April 5th, 2021")
    }

    func getSnapshot(in context: Context, completion: @escaping (PhotoEntry) -> ()) {
        let entry = loadPhotoEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PhotoEntry>) -> ()) {
        let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.plzwork.Achilles")

        var entries: [PhotoEntry] = []
        let fileManager = FileManager.default
        let now = Date()

        if let containerURL = containerURL {
            do {
                let contents = try fileManager.contentsOfDirectory(at: containerURL, includingPropertiesForKeys: nil)
                let dateFiles = contents.filter { $0.lastPathComponent.hasPrefix("featured_") && $0.pathExtension == "txt" }

                let sortedDateFiles = dateFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }

                for (index, dateURL) in sortedDateFiles.enumerated() {
                    if let timestampString = try? String(contentsOf: dateURL),
                       let timestamp = TimeInterval(timestampString) {

                        let creationDate = Date(timeIntervalSince1970: timestamp)
                        let formattedDate = formatDateNicely(creationDate)

                        let calendar = Calendar.current
                        let creationYear = calendar.component(.year, from: creationDate)
                        let currentYear = calendar.component(.year, from: now)

                        let yearsAgo = currentYear - creationYear
                        let yearsAgoText: String

                        if yearsAgo == 0 {
                            yearsAgoText = "This Year"
                        } else {
                            yearsAgoText = yearsAgo == 1 ? "1 Year Ago" : "\(yearsAgo) Years Ago"
                        }

                        // Load the image from the shared container
                        let image = UIImage(contentsOfFile: containerURL.appendingPathComponent("featured.jpg").path)

                        // Set the entry date to cycle every hour
                        let entryDate = Calendar.current.date(byAdding: .hour, value: index, to: now) ?? now

                        entries.append(PhotoEntry(
                            date: entryDate,
                            image: image,
                            yearsAgoText: yearsAgoText,
                            formattedDate: formattedDate
                        ))
                    }
                }
            } catch {
                print("❌ Error reading shared container: \(error)")
            }
        }

        if entries.isEmpty {
            entries = [loadPhotoEntry()] // fallback
        }

        // Create a timeline with entries
        let timeline = Timeline(entries: entries, policy: .after(entries.last?.date ?? now))
        completion(timeline)
    }

    private func loadPhotoEntry() -> PhotoEntry {
        let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.plzwork.Achilles")
        let imageURL = containerURL?.appendingPathComponent("featured.jpg")
        let dateURL = containerURL?.appendingPathComponent("featured_date.txt")

        let image = imageURL.flatMap { UIImage(contentsOfFile: $0.path) }

        var yearsAgo = 0
        var formattedDate = "Unknown"

        if let dateURL = dateURL,
           let timestampString = try? String(contentsOf: dateURL),
           let timestamp = TimeInterval(timestampString) {
            let creationDate = Date(timeIntervalSince1970: timestamp)
            formattedDate = formatDateNicely(creationDate)

            let calendar = Calendar.current
            let now = Date()
            let years = calendar.dateComponents([.year], from: creationDate, to: now).year ?? 0
            yearsAgo = max(years, 0)
        }

        return PhotoEntry(
            date: Date(),
            image: image,
            yearsAgoText: yearsAgo == 1 ? "1 Year Ago" : "\(yearsAgo) Years Ago",
            formattedDate: formattedDate
        )
    }

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
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }

        let year = Calendar.current.component(.year, from: date)
        return base + suffix + ", \(year)"
    }
}

struct PhotoWidgetEntryView: View {
    var entry: PhotoEntry

    // Define vignette darkness and radius range
    private let vignetteOpacity: Double = 0.6
    private let vignetteStartRadius: CGFloat = 100
    private let vignetteEndRadius: CGFloat = 450

    var body: some View {
        ZStack {
            // Image View with Vignette Effect
            if let img = entry.image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay(
                        RadialGradient(
                            gradient: Gradient(colors: [.clear, .black.opacity(vignetteOpacity)]),
                            center: .center,
                            startRadius: vignetteStartRadius,
                            endRadius: vignetteEndRadius
                        )
                        .allowsHitTesting(false)  // Prevents the overlay from blocking interaction
                    )
            } else {
                Text("No Image Found")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Text Overlay
            GeometryReader { geometry in
                VStack {
                    Spacer()

                    VStack(spacing: 0) {
                        Text(entry.yearsAgoText)
                            .font(.system(
                                size: min(geometry.size.width, geometry.size.height) * 0.12,
                                weight: .semibold,
                                design: .default
                            ))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text(entry.formattedDate)
                            .font(.system(
                                size: min(geometry.size.width, geometry.size.height) * 0.11,
                                weight: .regular,
                                design: .default
                            ))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    .padding(.bottom, geometry.size.height * 0.06)  // Increased padding to move the text up
                    .padding(.horizontal, geometry.size.width * 0.05)
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(10)
                }
                .padding(.bottom, geometry.size.height * 0.10) // Moved text 20% higher
            }
        }
        .containerBackground(for: .widget) {
            Color.black
        }
    }
}



struct YearsAgoWidget: Widget {
    let kind: String = "YearsAgoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PhotoWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Years Ago Photo")
        .description("Shows a memory from the past.")
        .supportedFamilies([.systemLarge])
    }
}

