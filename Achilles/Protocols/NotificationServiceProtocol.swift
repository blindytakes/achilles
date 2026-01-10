// NotificationServiceProtocol.swift
//
// This protocol defines the interface for scheduling and managing local notifications
// for the Throwbacks app. Local notifications remind users about memories
// from past years on the current date, but only after a period of inactivity.
//
// Key features:
// - Request notification permissions from the user
// - Schedule inactivity-based reminder notifications
// - Cancel scheduled notifications when user opens app
// - Check current notification authorization status

import Foundation
import UserNotifications

protocol NotificationServiceProtocol {
    /// Request notification permissions from the user
    func requestAuthorization() async -> Bool
    
    /// Schedule a notification to fire after X days of inactivity
    /// Each time the app opens, this gets reset, so user only sees it if they haven't opened in X days
    /// - Parameters:
    ///   - daysFromNow: Number of days from now to send the notification
    ///   - hour: Hour of day to send notification (0-23)
    ///   - minute: Minute of hour (0-59)
    ///   - yearsWithMemories: Array of years that have memories (for personalized message)
    func scheduleInactivityReminder(daysFromNow: Int, hour: Int, minute: Int, yearsWithMemories: [Int]) async
    
    /// Cancel all scheduled notifications
    func cancelAllNotifications()
    
    /// Check if notifications are currently authorized
    func checkAuthorizationStatus() async -> UNAuthorizationStatus
}

