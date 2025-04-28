import Foundation

extension Date {

    /// Formats the date as "Month DaySuffix" (e.g., "April 27th").
    func formatMonthDayWithOrdinal() -> String {
        let day = Calendar.current.component(.day, from: self)
        let suffix: String
        // Ordinal suffix logic (handles 11th, 12th, 13th correctly)
        if (11...13).contains(day % 100) {
            suffix = "th"
        } else {
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM d" // Format for month and day number
        let baseDate = dateFormatter.string(from: self)

        return "\(baseDate)\(suffix)"
    }

    /// Formats the date as "Month DaySuffix, Year" (e.g., "April 27th, 2025").
    /// Uses the formatMonthDayWithOrdinal() helper.
    func formatMonthDayOrdinalAndYear() -> String {
        let year = Calendar.current.component(.year, from: self)
        return "\(formatMonthDayWithOrdinal()), \(year)"
    }

    /// Formats the date using standard long date and shortened time (e.g., "April 27, 2025 at 9:22 PM").
    func formatLongDateShortTime() -> String {
        return self.formatted(date: .long, time: .shortened)
    }

    /// Formats the date using standard abbreviated date and shortened time (e.g., "Apr 27, 2025, 9:22 PM").
     func formatAbbreviatedDateShortTime() -> String {
         return self.formatted(date: .abbreviated, time: .shortened)
     }

    // Add other commonly used formats here if needed in the future.
}
