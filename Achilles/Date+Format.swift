import Foundation

extension Date {
    // MARK: – Cached Formatters
    
    private static let monthDayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMMM d"
        return df
    }()
    
    private static let longDateShortTimeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .short
        return df
    }()
    
    private static let abbreviatedDateShortTimeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()
    
    // MARK: – Ordinal Suffix Helper
    
    private var ordinalSuffix: String {
        let day = Calendar.current.component(.day, from: self)
        let mod100 = day % 100
        if (11...13).contains(mod100) { return "th" }
        switch day % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
    
    // MARK: – Public API
    
    /// “April 27th”
    func monthDayWithOrdinal() -> String {
        let base = Self.monthDayFormatter.string(from: self)
        return "\(base)\(ordinalSuffix)"
    }
    
    /// “April 27th, 2025”
    func monthDayWithOrdinalAndYear() -> String {
        let year = Calendar.current.component(.year, from: self)
        return "\(monthDayWithOrdinal()), \(year)"
    }
    
    /// “April 27, 2025 at 9:22 PM”
    func longDateShortTime() -> String {
        return Self.longDateShortTimeFormatter.string(from: self)
    }
    
    /// “Apr 27, 2025, 9:22 PM”
    func abbreviatedDateShortTime() -> String {
        return Self.abbreviatedDateShortTimeFormatter.string(from: self)
    }
}

