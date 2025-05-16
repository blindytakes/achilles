// SettingsStatisticsService.swift
import Foundation
// You might need to import Photos if MediaItem is used directly,
// but PhotoLibraryServiceProtocol abstracts that.

class SettingsStatisticsService {
    private let photoService: PhotoLibraryServiceProtocol

    // Allow dependency injection for testability, but default to a new instance
    init(photoService: PhotoLibraryServiceProtocol = PhotoLibraryService()) {
        self.photoService = photoService
    }

    func calculateTotalPhotosForCalendarDayFromPastYears(
        availablePastYearOffsets: [Int],
        currentMonthDayComponents: DateComponents // Expecting month and day
    ) async -> Int {
        var totalSum = 0
        let calendar = Calendar.current

        // If there are no past years with photos for this day, the sum is 0.
        if availablePastYearOffsets.isEmpty {
            return 0
        }

        // Iterate only through past year offsets (e.g., 1 for 1 year ago, 2 for 2 years ago, etc.)
        // 'availablePastYearOffsets' should already contain only positive integers.
        for yearOffset in Set(availablePastYearOffsets) {
            // It's good practice to ensure the offset is indeed for a past year.
            // Though `availablePastYearOffsets` from PhotoViewModel should already ensure this.
            guard yearOffset > 0 else { continue }

            var targetDateComponents = calendar.dateComponents([.year], from: Date()) // Get current year component
            targetDateComponents.year! -= yearOffset // Calculate the target past year
            targetDateComponents.month = currentMonthDayComponents.month // Set to current month
            targetDateComponents.day = currentMonthDayComponents.day     // Set to current day

            if let specificDateInTargetYear = calendar.date(from: targetDateComponents) {
                let countForThisDate = await fetchPhotoCountFromService(forDate: specificDateInTargetYear)
                totalSum += countForThisDate
            } else {
                print("SettingsStatisticsService: Could not construct a valid date for yearOffset: \(yearOffset), month: \(String(describing: currentMonthDayComponents.month)), day: \(String(describing: currentMonthDayComponents.day))")
            }
        }
        return totalSum
    }

    // Helper to wrap the PhotoLibraryService call and make it async
    private func fetchPhotoCountFromService(forDate date: Date) async -> Int {
        return await withCheckedContinuation { continuation in
            self.photoService.fetchItems(for: date) { result in
                switch result {
                case .success(let items):
                    continuation.resume(returning: items.count)
                case .failure(let error):
                    print("SettingsStatisticsService: Error fetching items for date \(date): \(error.localizedDescription)")
                    continuation.resume(returning: 0) // Return 0 on error for this specific date
                }
            }
        }
    }
}
