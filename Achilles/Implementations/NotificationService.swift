// NotificationService.swift
//
// This service handles local push notifications for the Throwbacks app.
// It schedules reminders that only fire if the user hasn't opened the app
// in a configurable number of days (default: 3 days).
//
// How it works:
// - Every time the app opens, we cancel any pending notification and schedule a new one for X days out
// - If user opens the app again before X days, the notification gets cancelled and rescheduled
// - Only if the user doesn't open for X days will they receive the notification
//
// This approach respects active users while re-engaging inactive ones.

import Foundation
import UserNotifications

class NotificationService: NotificationServiceProtocol {
    
    // MARK: - Constants
    private struct Constants {
        static let inactivityReminderIdentifier = "com.throwbacks.inactivityReminder"
    }
    
    // MARK: - Properties
    private let notificationCenter = UNUserNotificationCenter.current()
    
    // MARK: - Authorization
    
    /// Request notification permissions from the user
    /// - Returns: Boolean indicating if authorization was granted
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            print("📱 Local notification permission granted: \(granted)")
            return granted
        } catch {
            print("❌ Error requesting notification authorization: \(error)")
            return false
        }
    }
    
    /// Check current notification authorization status
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await notificationCenter.notificationSettings()
        return settings.authorizationStatus
    }
    
    // MARK: - Scheduling
    
    /// Schedule a notification to fire after X days of inactivity
    /// Call this every time the app opens - it cancels any existing notification and reschedules
    /// - Parameters:
    ///   - daysFromNow: Number of days from now to trigger (default: 3)
    ///   - hour: Hour of day to send (0-23, default: 9 AM)
    ///   - minute: Minute of hour (0-59, default: 0)
    ///   - yearsWithMemories: Years with memories for personalized message
    func scheduleInactivityReminder(
        daysFromNow: Int = 3,
        hour: Int = 9,
        minute: Int = 0,
        yearsWithMemories: [Int] = []
    ) async {
        // First check if we have authorization
        let status = await checkAuthorizationStatus()
        guard status == .authorized else {
            print("⚠️ Cannot schedule notification - not authorized (status: \(status))")
            return
        }
        
        // Cancel any existing inactivity reminder (we're resetting the timer)
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: [Constants.inactivityReminderIdentifier]
        )
        
        // Calculate the target date (X days from now at specified time)
        guard let targetDate = calculateTargetDate(
            daysFromNow: daysFromNow,
            hour: hour,
            minute: minute
        ) else {
            print("❌ Could not calculate target date for notification")
            return
        }
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Your memories miss you! 📸"
        content.body = createNotificationBody(yearsWithMemories: yearsWithMemories)
        content.sound = .default
        content.badge = 1
        
        // Create trigger for the specific date
        let triggerComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: targetDate
        )
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: triggerComponents,
            repeats: false
        )
        
        // Create and schedule the request
        let request = UNNotificationRequest(
            identifier: Constants.inactivityReminderIdentifier,
            content: content,
            trigger: trigger
        )
        
        do {
            try await notificationCenter.add(request)
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            print("✅ Inactivity reminder scheduled for: \(formatter.string(from: targetDate))")
        } catch {
            print("❌ Error scheduling inactivity reminder: \(error)")
        }
    }
    
    // MARK: - Cancellation
    
    /// Cancel all scheduled notifications
    func cancelAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
        // Clear badge
        UNUserNotificationCenter.current().setBadgeCount(0) { error in
            if let error = error {
                print("❌ Error clearing badge: \(error)")
            }
        }
        print("🗑️ All notifications cancelled")
    }
    
    // MARK: - Helper Methods
    
    /// Calculate the target date for the notification
    private func calculateTargetDate(daysFromNow: Int, hour: Int, minute: Int) -> Date? {
        let calendar = Calendar.current
        
        // Get date X days from now
        guard let futureDate = calendar.date(byAdding: .day, value: daysFromNow, to: Date()) else {
            return nil
        }
        
        // Set the time to the specified hour:minute
        var components = calendar.dateComponents([.year, .month, .day], from: futureDate)
        components.hour = hour
        components.minute = minute
        components.second = 0
        
        return calendar.date(from: components)
    }
    
    /// Create a personalized notification body based on available memories
    private func createNotificationBody(yearsWithMemories: [Int]) -> String {
        guard !yearsWithMemories.isEmpty else {
            return "Open Throwbacks to see your memories from this day in past years!"
        }
        
        let sortedYears = yearsWithMemories.sorted()
        
        switch sortedYears.count {
        case 1:
            let year = sortedYears[0]
            return "You have memories from \(year) year\(year == 1 ? "" : "s") ago waiting for you!"
        case 2:
            return "Memories from \(sortedYears[0]) and \(sortedYears[1]) years ago are waiting!"
        case 3:
            return "Memories from \(sortedYears[0]), \(sortedYears[1]), and \(sortedYears[2]) years ago!"
        default:
            return "You have memories from \(sortedYears.count) different years waiting for you!"
        }
    }
    
    // MARK: - Debug Helpers
    
    /// Print all pending notifications (useful for debugging)
    func printPendingNotifications() async {
        let requests = await notificationCenter.pendingNotificationRequests()
        print("📋 Pending notifications (\(requests.count)):")
        for request in requests {
            print("  - \(request.identifier): \(request.content.title)")
            if let trigger = request.trigger as? UNCalendarNotificationTrigger {
                print("    Trigger: \(trigger.dateComponents)")
            }
        }
    }
}
