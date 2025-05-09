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
      
      // TEMPORARY: Create AuthViewModel and immediately sign out for testing
      let vm = AuthViewModel()      
      // Continue with your existing initialization
      _authVM = StateObject(wrappedValue: vm)
      
      // Give the delegate the same instance, *without* ever reading authVM
      // Note: We need to use the property wrapper's projectedValue here
      // because we're in the initializer
      _appDelegate.wrappedValue.authVM = vm
    }
    
  var body: some Scene {
    WindowGroup {
      rootView
        .environmentObject(authVM)
    }
    .onChange(of: photoStatus) {
      // Access photoStatus directly inside the closure
      print("📸 Photo-library status is now \(photoStatus)")
    }
  }
  
    @ViewBuilder
    private var rootView: some View {
        if authVM.user == nil {
            // Use the new WelcomeView for authentication and initial onboarding
            WelcomeView()
        } else if photoStatus != .authorized && photoStatus != .limited {
            // Show photo permission screen if needed
            AuthorizationRequiredView(status: photoStatus) {
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { new in
                    DispatchQueue.main.async { photoStatus = new }
                }
            }
        } else {
            // Main app content
            ContentView()
        }
    }
    }
