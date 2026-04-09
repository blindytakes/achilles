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
    }
    
    // MARK: - User Authentication
    func logSignUp(method: String) {
        Analytics.logEvent(AnalyticsEventSignUp, parameters: [AnalyticsParameterMethod: method])
    }
    
    func logLogin(method: String) {
        Analytics.logEvent(AnalyticsEventLogin, parameters: [AnalyticsParameterMethod: method])
    }
    
    // MARK: - Content Engagement
    func logPhotoView(yearsAgo: Int, hasLocation: Bool = false, isVideo: Bool = false) {
        Analytics.logEvent("photo_view", parameters: [
            "years_ago": yearsAgo, "has_location": hasLocation,
            "content_type": isVideo ? "video" : "photo"
        ])
    }
    
    func logPhotoShare(yearsAgo: Int, shareMethod: String) {
        Analytics.logEvent(AnalyticsEventShare, parameters: [
            "content_type": "photo", "years_ago": yearsAgo, "method": shareMethod
        ])
    }
    
    // MARK: - Memory Discovery
    func logMemoryDiscovery(yearsAgo: Int, photoCount: Int) {
        Analytics.logEvent("memory_discovery", parameters: [
            "years_ago": yearsAgo, "photo_count": photoCount
        ])
    }
    
    func logFeaturedPhotoTap(yearsAgo: Int) {
        Analytics.logEvent("featured_photo_tap", parameters: ["years_ago": yearsAgo])
    }
    
    // MARK: - Feature Usage
    func logLocationView(yearsAgo: Int) {
        Analytics.logEvent("location_view", parameters: [
            "years_ago": yearsAgo, "feature": "location_panel"
        ])
    }
    
    func logTutorialProgress(step: String, completed: Bool) {
        Analytics.logEvent("tutorial_progress", parameters: [
            "tutorial_step": step, "completed": completed
        ])
    }
    
    func logTutorialComplete(timeSpent: TimeInterval) {
        Analytics.logEvent("tutorial_complete", parameters: ["time_spent_seconds": Int(timeSpent)])
    }
    
    // MARK: - User Properties
    func setUserProperties(isAnonymous: Bool, daysSinceSignup: Int? = nil) {
        Analytics.setUserProperty(isAnonymous ? "anonymous" : "registered", forName: "user_type")
        if let days = daysSinceSignup {
            Analytics.setUserProperty(String(days), forName: "days_since_signup")
        }
    }
    
    // MARK: - Search and Navigation
    func logYearSwipe(fromYear: Int, toYear: Int) {
        Analytics.logEvent("year_swipe", parameters: [
            "from_year": fromYear, "to_year": toYear,
            "direction": toYear > fromYear ? "forward" : "backward"
        ])
    }
    
    func logPhotoLibraryAccess(granted: Bool) {
        Analytics.logEvent("photo_library_access", parameters: ["granted": granted])
    }
    
    // MARK: - Error Tracking
    func logError(_ error: Error, context: String) {
        Analytics.logEvent("app_error", parameters: [
            "error_type": String(describing: type(of: error)),
            "context": context,
            "error_description": error.localizedDescription
        ])

        TelemetryService.shared.recordSpan(
            name: "error", durationMs: 0,
            attributes: [
                "error.type": String(describing: type(of: error)),
                "error.description": error.localizedDescription,
                "error.context": context
            ],
            status: .error
        )
        TelemetryService.shared.incrementCounter(
            name: "throwbaks.errors.total",
            attributes: ["error.type": String(describing: type(of: error)), "error.context": context]
        )
        TelemetryService.shared.log(
            error.localizedDescription, severity: .error,
            attributes: ["error.type": String(describing: type(of: error)), "error.context": context]
        )
    }
    
    // MARK: - Performance Events
    func logPhotoLoadTime(yearsAgo: Int, loadTimeMs: Int) {
        Analytics.logEvent("photo_load_performance", parameters: [
            "years_ago": yearsAgo, "load_time_ms": loadTimeMs
        ])
    }
    
    // MARK: - Engagement Metrics
    func logSessionDuration(durationSeconds: Int) {
        Analytics.logEvent("session_duration", parameters: ["duration_seconds": durationSeconds])
    }
    
    func logDailyActiveUser() {
        Analytics.logEvent("daily_active_user", parameters: [
            "date": DateFormatter.yyyyMMdd.string(from: Date())
        ])
    }

    // MARK: - Collage Events

    func logCollageSourceView(source: String) {
        Analytics.logEvent("collage_source_view", parameters: ["source_type": source])
    }

    func logCollageGenerated(source: String, photoCount: Int, durationMs: Int) {
        Analytics.logEvent("collage_generated", parameters: [
            "source_type": source, "photo_count": photoCount, "duration_ms": durationMs
        ])
    }

    func logCollageSaved(source: String) {
        Analytics.logEvent("collage_saved", parameters: ["source_type": source])
    }

    func logCollageLayoutSwitched(layout: String) {
        Analytics.logEvent("collage_layout_switched", parameters: ["layout": layout])
    }

    // MARK: - App Lifecycle

    func logAppOpen(source: String, userType: String? = nil) {
        var params: [String: Any] = ["source": source]
        if let userType = userType { params["user_type"] = userType }
        Analytics.logEvent("app_open", parameters: params)
    }

    func logDeepLink(url: String) {
        Analytics.logEvent("app_open", parameters: ["source": "deep_link", "url": url])
    }

    func logOnboardingStart(type: String) {
        Analytics.logEvent("onboarding_start", parameters: ["onboarding_type": type])
    }

    func logNotificationsScheduled(inactivityDays: Int, memoriesCount: Int) {
        Analytics.logEvent("notifications_scheduled", parameters: [
            "inactivity_days": inactivityDays, "memories_count": memoriesCount
        ])
    }

    func logPhotoPermissionChanged(status: String) {
        Analytics.logEvent("photo_permission_changed", parameters: ["new_status": status])
    }

    func logCarouselYearSelected(yearsAgo: Int) {
        Analytics.logEvent("carousel_year_selected", parameters: ["years_ago": yearsAgo])
    }

    func setUserType(_ type: String) {
        Analytics.setUserProperty(type, forName: "user_type")
    }

    // MARK: - App Configuration

    func enableAnalyticsCollection(_ enabled: Bool) {
        Analytics.setAnalyticsCollectionEnabled(enabled)
    }

    func setAppVersion(_ version: String?) {
        Analytics.setUserProperty(version, forName: "app_version")
    }

    func setBuildNumber(_ build: String?) {
        Analytics.setUserProperty(build, forName: "build_number")
    }
}
