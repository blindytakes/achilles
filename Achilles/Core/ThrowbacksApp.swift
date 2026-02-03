// AchillesApp.swift
//
// This is the main application file that configures the app, handles Firebase setup,
// manages local notifications, and controls the app's navigation flow.
//
// Key features:
// - Initializes Firebase services during app startup
// - Configures Firebase Analytics for user behavior tracking
// - Schedules local notifications for inactive users (3+ days)
// - Manages authentication state through AuthViewModel
// - Controls the app's navigation flow based on:
//   - Authentication state (logged in/out)
//   - Onboarding status
//   - Daily welcome requirements
//   - Photo library permissions
// - Handles photo library authorization changes
//
// The file includes two main components:
// 1. AppDelegate: Manages Firebase configuration and notification handling
// 2. ThrowbaksApp: The SwiftUI app structure that determines which view to display
//    based on the current application state

import SwiftUI
import Firebase            // FirebaseCore
import FirebaseAuth        // brings in `Auth`
import FirebaseFirestore   // Firestore access
import FirebaseAnalytics   // Firebase Analytics
import UserNotifications
import PhotosUI            // for `PHPhotoLibrary`
import GoogleSignIn

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var authVM: AuthViewModel?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        // Firebase is already configured in ThrowbaksApp.init()
        
        // Verify authVM is wired up
        if authVM == nil {
            print("❌ CRITICAL: authVM is nil in AppDelegate!")
        } else {
            print("✅ authVM properly wired to AppDelegate")
        }
        
        // Set up notification center delegate for handling local notifications
        UNUserNotificationCenter.current().delegate = self

        return true
    }

    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("📬 Received notification while app in foreground")
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        print("👆 User tapped notification")
        completionHandler()
    }
}

@main
struct ThrowbaksApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authVM: AuthViewModel
    @StateObject private var photoViewModel = PhotoViewModel()
    @State private var photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @AppStorage("lastIntroVideoPlayDate") private var lastIntroVideoPlayDate: Double = 0.0
    
    // Local notification service for daily memory reminders
    private let notificationService = NotificationService()

    init() {
        // 1. Configure Firebase first
        FirebaseApp.configure()
        
        // 2. Enable Firebase Analytics
        Analytics.setAnalyticsCollectionEnabled(true)
        
        // 3. Set initial user properties for better segmentation
        Analytics.setUserProperty(
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            forName: "app_version"
        )
        Analytics.setUserProperty(
            Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            forName: "build_number"
        )
        
        // 4. Configure Google Sign-In
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: FirebaseApp.app()?.options.clientID ?? "")

        // 5. Set up AuthViewModel and wire into AppDelegate
        let vm = AuthViewModel()
        _authVM = StateObject(wrappedValue: vm)
        appDelegate.authVM = vm
        
        // 6. Initialize telemetry (Grafana Cloud traces + metrics + logs)
        TelemetryService.shared.initialize()
        TelemetryService.shared.incrementCounter(name: "throwbaks.sessions.total")
        TelemetryService.shared.log("app_launched")

        // 7. Log app initialization
        print("🔥 Firebase Analytics enabled")
        print("✅ Analytics setup complete")
    }
    
  /// Write a `lastOpened` timestamp into Firestore when the app enters foreground
  private func updateLastOpened() {
    guard let uid = Auth.auth().currentUser?.uid else { return }
    let ref = Firestore.firestore().collection("users").document(uid)
    ref.updateData(["lastOpened": FieldValue.serverTimestamp()]) { err in
      if let err = err {
        print("❌ Failed to update lastOpened:", err)
      }
    }
  }

    /// Clear all delivered notifications when app opens
    private func clearDeliveredNotifications() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        // Also clear the badge count
        UNUserNotificationCenter.current().setBadgeCount(0) { error in
            if let error = error {
                print("❌ Error clearing badge: \(error)")
            }
        }
        print("🗑️ Cleared all delivered notifications")
    }
  /// Determine whether to show the intro video based on the last play date
  private func shouldPlayIntroVideo() -> Bool {
    if lastIntroVideoPlayDate == 0.0 {
      return true
    }
    let lastPlayDate = Date(timeIntervalSince1970: lastIntroVideoPlayDate)
    return !Calendar.current.isDateInToday(lastPlayDate)
  }
  
  /// Schedule local notifications for memory reminders (only if inactive for 3+ days)
  private func scheduleDailyMemoryNotifications() async {
      // Check and request authorization if needed
      let status = await notificationService.checkAuthorizationStatus()
      
      if status == .notDetermined {
          let granted = await notificationService.requestAuthorization()
          guard granted else {
              print("📱 User declined local notification permissions")
              return
          }
      } else if status != .authorized {
          print("📱 Local notifications not authorized (status: \(status))")
          return
      }
      
      // Schedule a notification for 3 days from now
      // If user opens the app before then, this gets cancelled and rescheduled
      await notificationService.scheduleInactivityReminder(
          daysFromNow: 2,
          hour: 9,
          minute: 0,
          yearsWithMemories: photoViewModel.availableYearsAgo
      )
      
      // Log the scheduling for analytics
      Analytics.logEvent("notifications_scheduled", parameters: [
          "inactivity_days": 2,
          "memories_count": photoViewModel.availableYearsAgo.count
      ])
      
      print("✅ Inactivity notification scheduled for 2 days from now")
  }

  var body: some Scene {
    WindowGroup {
      rootView
        .environmentObject(authVM)
        .environmentObject(photoViewModel)
        // Update lastOpened on enter foreground
        .onReceive(
          NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification
          )
        ) { _ in
          updateLastOpened()
          TelemetryService.shared.log("app_foreground")

          // Log app open event for Firebase Analytics
          Analytics.logEvent("app_open", parameters: [
            "source": "foreground_return"
          ])
        }
        // Reset welcome flag on resign active
        .onReceive(
          NotificationCenter.default.publisher(
            for: UIApplication.willResignActiveNotification
          )
        ) { _ in
          authVM.showMainApp = false
        }
        .background(Color.black)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onOpenURL { url in
            print("✅ App received URL: \(url)")
            GIDSignIn.sharedInstance.handle(url)
            
            // Log deep link open for Firebase Analytics
            Analytics.logEvent("app_open", parameters: [
                "source": "deep_link",
                "url": url.absoluteString
            ])
        }
    }
     .onChange(of: photoStatus) { newStatus in
      print("📸 Photo-library status is now \(newStatus)")
      
      // Log photo permission changes for Firebase Analytics
      Analytics.logEvent("photo_permission_changed", parameters: [
        "new_status": String(describing: newStatus)
      ])
    }
  }

    @ViewBuilder
    private var rootView: some View {
        if authVM.isInitializing {
            ZStack {
                Color.black.ignoresSafeArea()
                ProgressView("Loading…")
                    .progressViewStyle(CircularProgressViewStyle())
            }
            .onAppear {
                // Log app initialization screen
                Analytics.logEvent(AnalyticsEventScreenView, parameters: [
                    AnalyticsParameterScreenName: "app_initializing",
                    AnalyticsParameterScreenClass: "LoadingView"
                ])
            }
        } else if authVM.user == nil {
            LoginSignupView()
                .onAppear {
                    clearDeliveredNotifications()

                    // Log login/signup screen view
                    Analytics.logEvent(AnalyticsEventScreenView, parameters: [
                        AnalyticsParameterScreenName: "login_signup",
                        AnalyticsParameterScreenClass: "LoginSignupView"
                    ])
                    
                    // Log daily active user
                    Analytics.logEvent("daily_active_user", parameters: [
                        "date": DateFormatter.yyyyMMdd.string(from: Date())
                    ])
                }
        } else {
            // All authenticated users (registered AND guests): decide between intro video or main content
            if !shouldPlayIntroVideo() || authVM.showMainApp {
                ContentView()
                    .onAppear {
                        
                        clearDeliveredNotifications()
                        
                        // Log main content screen view
                        Analytics.logEvent(AnalyticsEventScreenView, parameters: [
                            AnalyticsParameterScreenName: "main_content",
                            AnalyticsParameterScreenClass: "ContentView"
                        ])
                        
                        // Log app open event
                        Analytics.logEvent("app_open", parameters: [
                            "source": "direct",
                            "user_type": authVM.user?.isAnonymous == true ? "anonymous" : "registered"
                        ])
                        
                        // Set user properties
                        Analytics.setUserProperty(
                            authVM.user?.isAnonymous == true ? "anonymous" : "registered",
                            forName: "user_type"
                        )
                        
                        // Schedule daily memory notifications
                        Task {
                            await scheduleDailyMemoryNotifications()
                        }
                    }
            } else {
                DailyWelcomeView()
                    .onAppear {
                        // Log daily welcome screen view
                        Analytics.logEvent(AnalyticsEventScreenView, parameters: [
                            AnalyticsParameterScreenName: "daily_welcome",
                            AnalyticsParameterScreenClass: "DailyWelcomeView"
                        ])
                        
                        // Log onboarding start
                        Analytics.logEvent("onboarding_start", parameters: [
                            "onboarding_type": "daily_welcome"
                        ])
                    }
            }
        }
    }
}

// MARK: - DateFormatter Extension for Analytics
private extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

