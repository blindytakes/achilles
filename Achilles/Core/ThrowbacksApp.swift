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
// 2. ThrowbaksApp: The SwiftUI app structure that determines which view to display
//    based on the current application state

import SwiftUI
import Firebase            // FirebaseCore
import FirebaseAuth        // brings in `Auth`
import FirebaseMessaging   // brings in `Messaging`
import FirebaseFirestore   // Firestore access
import UserNotifications
import PhotosUI            // for `PHPhotoLibrary`
import SplunkOtel
import SplunkOtelCrashReporting
import GoogleSignIn 

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    var authVM: AuthViewModel?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        // Firebase is already configured in ThrowbaksApp.init()
        
        // 2) Verify authVM is wired up
        if authVM == nil {
            print("❌ CRITICAL: authVM is nil in AppDelegate!")
        } else {
            print("✅ authVM properly wired to AppDelegate")
        }
        
        // 3) Request push notification permissions
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                print("📱 Push notification permission granted: \(granted)")
                if let error = error {
                    print("❌ Push notification permission error: \(error)")
                } else if granted {
                    DispatchQueue.main.async {
                        application.registerForRemoteNotifications()
                    }
                }
            }

        // 4) Set up FCM
        Messaging.messaging().delegate = self

        return true
    }


    func application(
      _ application: UIApplication,
      didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
      print("✅ Successfully registered for remote notifications")
      // Tell FCM about the APNs token
      Messaging.messaging().apnsToken = deviceToken

      // **Now** fetch your FCM token, since APNs is set
      Messaging.messaging().token { token, error in
        if let error = error {
          print("❌ Error fetching FCM token after APNs registration: \(error)")
          return
        }
        guard let token = token else {
          print("⚠️ FCM token is nil even after APNs registration")
          return
        }
        print("✅ FCM token after APNs registration: \(token)")
        Task {
          await self.authVM?.savePushToken(token)
        }
      }
    }

    // APNs registration failure
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ Failed to register for remote notifications: \(error)")
    }

    // FCM token refresh (keep your existing one, just add logging)
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else {
            print("⚠️ FCM token refresh returned nil")
            return
        }
        print("🔄 FCM token refreshed: \(token)")

        Task {
            await authVM?.savePushToken(token)
        }
    }

    // Keep your existing foreground notification handler
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("📬 Received notification while app in foreground")
        completionHandler([.banner, .sound, .badge])
    }
    
    // Add notification tap handler
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

    init() {
        
        
        FirebaseApp.configure()
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: FirebaseApp.app()?.options.clientID ?? "")


        // Splunk RUM initialization only
        SplunkRumBuilder(
            realm: "us1",
            rumAuth: "L6lXNT6-fbQFAQRU35-MYA"
        )
        .debug(enabled: true)
        .deploymentEnvironment(environment: "dev")
        .setApplicationName("Throwbacks")
        .build()
        SplunkRumCrashReporting.start()

        // Set up AuthViewModel and wire into AppDelegate
        let vm = AuthViewModel()
        _authVM = StateObject(wrappedValue: vm)
        appDelegate.authVM = vm
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

  /// Determine whether to show the intro video based on the last play date
  private func shouldPlayIntroVideo() -> Bool {
    if lastIntroVideoPlayDate == 0.0 {
      return true
    }
    let lastPlayDate = Date(timeIntervalSince1970: lastIntroVideoPlayDate)
    return !Calendar.current.isDateInToday(lastPlayDate)
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
        }
    }
    .onChange(of: photoStatus) { newStatus in
      print("📸 Photo-library status is now \(newStatus)")
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
        } else if authVM.user == nil {
            LoginSignupView()
        } else {
            // All authenticated users (registered AND guests): decide between intro video or main content
            if !shouldPlayIntroVideo() || authVM.showMainApp {
                ContentView()
            } else {
                DailyWelcomeView()
            }
        }
    }
    }
