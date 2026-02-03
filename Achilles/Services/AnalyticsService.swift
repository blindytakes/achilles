
import Foundation
import FirebaseAnalytics

class AnalyticsService {
    static let shared = AnalyticsService()
    
    private init() {}
    
    // MARK: - Screen Views
    func logScreenView(_ screenName: String, screenClass: String? = nil) {
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [
            AnalyticsParameterScreenName: screenName,
            AnalyticsParameterScreenClass: screenClass ?? screenName
        ])
        print("🔥 Analytics: Screen view - \(screenName)")
    }
    
    // MARK: - User Authentication
    func logSignUp(method: String) {
        Analytics.logEvent(AnalyticsEventSignUp, parameters: [
            AnalyticsParameterMethod: method
        ])
        print("🔥 Analytics: Sign up - \(method)")
    }
    
    func logLogin(method: String) {
        Analytics.logEvent(AnalyticsEventLogin, parameters: [
            AnalyticsParameterMethod: method
        ])
        print("🔥 Analytics: Login - \(method)")
    }
    
    // MARK: - Content Engagement
    func logPhotoView(yearsAgo: Int, hasLocation: Bool = false, isVideo: Bool = false) {
        Analytics.logEvent("photo_view", parameters: [
            "years_ago": yearsAgo,
            "has_location": hasLocation,
            "content_type": isVideo ? "video" : "photo"
        ])
        print("🔥 Analytics: \(isVideo ? "Video" : "Photo") view - \(yearsAgo) years ago")
    }
    
    func logPhotoShare(yearsAgo: Int, shareMethod: String) {
        Analytics.logEvent(AnalyticsEventShare, parameters: [
            "content_type": "photo",
            "years_ago": yearsAgo,
            "method": shareMethod
        ])
        print("🔥 Analytics: Photo shared via \(shareMethod)")
    }
    
    // MARK: - Memory Discovery
    func logMemoryDiscovery(yearsAgo: Int, photoCount: Int) {
        Analytics.logEvent("memory_discovery", parameters: [
            "years_ago": yearsAgo,
            "photo_count": photoCount
        ])
        print("🔥 Analytics: Memory discovered - \(photoCount) photos from \(yearsAgo) years ago")
    }
    
    func logFeaturedPhotoTap(yearsAgo: Int) {
        Analytics.logEvent("featured_photo_tap", parameters: [
            "years_ago": yearsAgo
        ])
        print("🔥 Analytics: Featured photo tapped - \(yearsAgo) years ago")
    }
    
    // MARK: - Feature Usage
    func logLocationView(yearsAgo: Int) {
        Analytics.logEvent("location_view", parameters: [
            "years_ago": yearsAgo,
            "feature": "location_panel"
        ])
        print("🔥 Analytics: Location viewed for \(yearsAgo) years ago")
    }
    
    func logTutorialProgress(step: String, completed: Bool) {
        Analytics.logEvent("tutorial_progress", parameters: [
            "tutorial_step": step,
            "completed": completed
        ])
        print("🔥 Analytics: Tutorial \(step) - \(completed ? "completed" : "started")")
    }
    
    func logTutorialComplete(timeSpent: TimeInterval) {
        Analytics.logEvent("tutorial_complete", parameters: [
            "time_spent_seconds": Int(timeSpent)
        ])
        print("🔥 Analytics: Tutorial completed in \(Int(timeSpent)) seconds")
    }
    
    // MARK: - User Properties
    func setUserProperties(isAnonymous: Bool, daysSinceSignup: Int? = nil) {
        Analytics.setUserProperty(isAnonymous ? "anonymous" : "registered", forName: "user_type")
        
        if let days = daysSinceSignup {
            Analytics.setUserProperty(String(days), forName: "days_since_signup")
        }
        
        print("🔥 Analytics: User properties set - \(isAnonymous ? "anonymous" : "registered")")
    }
    
    // MARK: - Search and Navigation
    func logYearSwipe(fromYear: Int, toYear: Int) {
        Analytics.logEvent("year_swipe", parameters: [
            "from_year": fromYear,
            "to_year": toYear,
            "direction": toYear > fromYear ? "forward" : "backward"
        ])
    }
    
    func logPhotoLibraryAccess(granted: Bool) {
        Analytics.logEvent("photo_library_access", parameters: [
            "granted": granted
        ])
    }
    
    // MARK: - Error Tracking
    func logError(_ error: Error, context: String) {
        Analytics.logEvent("app_error", parameters: [
            "error_type": String(describing: type(of: error)),
            "context": context,
            "error_description": error.localizedDescription
        ])
        print("🔥 Analytics: Error logged - \(error.localizedDescription)")

        TelemetryService.shared.recordSpan(
            name: "error",
            durationMs: 0,
            attributes: [
                "error.type":        String(describing: type(of: error)),
                "error.description": error.localizedDescription,
                "error.context":     context
            ],
            status: .error
        )
    }
    
    // MARK: - Performance Events
    func logPhotoLoadTime(yearsAgo: Int, loadTimeMs: Int) {
        Analytics.logEvent("photo_load_performance", parameters: [
            "years_ago": yearsAgo,
            "load_time_ms": loadTimeMs
        ])
    }
    
    // MARK: - Engagement Metrics
    func logSessionDuration(durationSeconds: Int) {
        Analytics.logEvent("session_duration", parameters: [
            "duration_seconds": durationSeconds
        ])
    }
    
    func logDailyActiveUser() {
        Analytics.logEvent("daily_active_user", parameters: [
            "date": DateFormatter.yyyyMMdd.string(from: Date())
        ])
    }
}

// MARK: - DateFormatter Extension
private extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
