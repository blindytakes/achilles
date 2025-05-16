// AchillesApp.swift
//
// This is the main application file that configures the app, handles Firebase setup,
// manages push notifications, and controls the app's navigation flow.
//
// Key features:
// - Initializes Firebase services during app startup
// - Configures push notifications with Firebase Cloud Messaging (FCM)
// - Manages authentication state through AuthViewModel
// - Controls the app's navigation flow based on:
//   - Authentication state (logged in/out)
//   - Onboarding status
//   - Daily welcome requirements
//   - Photo library permissions
// - Handles photo library authorization changes
//
// The file includes two main components:
// 1. AppDelegate: Manages Firebase configuration, push notification permissions,
//    and FCM token handling
// 2. AchillesApp: The SwiftUI app structure that determines which view to display
//    based on the current application state
//
// The app maintains proper coordination between the UIKit-based AppDelegate
// and the SwiftUI app structure through careful state management.


import SwiftUI
import Firebase            // FirebaseCore
import FirebaseAuth        // brings in `Auth`
import FirebaseMessaging   // brings in `Messaging`
import FirebaseFirestore   // if you're using Firestore anywhere
import UserNotifications
import PhotosUI            // for `PHPhotoLibrary`
import SplunkOtel
import SplunkOtelCrashReporting


class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
  // Add a reference to AuthViewModel
  var authVM: AuthViewModel?
  
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    // Firebase configuration moved to AchillesApp.init()
    
    // 1) Ask permission for alerts/badges/sounds
    UNUserNotificationCenter.current().delegate = self
    UNUserNotificationCenter.current()
      .requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
        guard granted else { return }
        DispatchQueue.main.async {
          application.registerForRemoteNotifications()
        }
      }

    // 2) Wire up FCM
    Messaging.messaging().delegate = self

    return true
  }

  // APNs → FCM
  func application(_ application: UIApplication,
                   didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Messaging.messaging().apnsToken = deviceToken
  }

  // This is called when FCM gives you (or refreshes) your token
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    guard let fcmToken = fcmToken else { return }
    print("🔑 FCM token:", fcmToken)
    
    // Forward to AuthViewModel if available
    Task {
      await authVM?.savePushToken(fcmToken)
    }
  }

  // Optional: show notifications while app is foreground
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification,
                              withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.banner, .sound])
  }
}

@main
struct ThrowbaksApp: App {  // Changed app name to match your new branding
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @StateObject private var authVM: AuthViewModel
  @State private var photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    
    init() {
      FirebaseApp.configure()
        // — new Splunk RUM setup (➋) —
        SplunkRumBuilder(
          realm:       "us1",                     // ← your realm
          rumAuth:     "L6lXNT6-fbQFAQRU35-MYA"    // ← your real RUM token
        )
        .debug(enabled: true)
        .deploymentEnvironment(environment: "dev")
        .setApplicationName("Throwbacks")
        .build()
        
        SplunkRumCrashReporting.start()


      let vm = AuthViewModel()
      _authVM = StateObject(wrappedValue: vm)
      _appDelegate.wrappedValue.authVM = vm
    }
    
    // In ThrowbacksApp.swift, add this to the WindowGroup
    var body: some Scene {
        WindowGroup {
            rootView
                .environmentObject(authVM)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    // Reset the flag when app goes to background
                    authVM.showMainApp = false
                }
        }
        .onChange(of: photoStatus) {
            // Access photoStatus directly inside the closure
            print("📸 Photo-library status is now \(photoStatus)")
        }
    }
  
    @ViewBuilder
    private var rootView: some View {
        if authVM.isInitializing {
            // Show loading while Firebase initializes
            ZStack {
                Color.white.ignoresSafeArea()
                ProgressView("Loading...")
                    .progressViewStyle(CircularProgressViewStyle())
            }
        } else if authVM.user == nil {
            // Not logged in - show welcome/login screen
            LoginSignupView()
        } else if authVM.showMainApp {
            // User has clicked through daily welcome
            ContentView()
        } else {
            // User is logged in - show daily welcome every time
            DailyWelcomeView()
        }
    }
}
  
