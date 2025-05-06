import SwiftUI
import Firebase            // FirebaseCore
import FirebaseAuth        // brings in `Auth`
import FirebaseMessaging   // brings in `Messaging`
import FirebaseFirestore   // if you’re using Firestore anywhere
import UserNotifications
import PhotosUI            // for `PHPhotoLibrary`


class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    FirebaseApp.configure()

    // 1) Ask permission for alerts/badges/sounds
    UNUserNotificationCenter.current().delegate = self
    UNUserNotificationCenter.current()
      .requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
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
    guard let fcmToken = fcmToken,
          let uid = Auth.auth().currentUser?.uid else { return }

    print("🔑 FCM token:", fcmToken)
    // Save into Firestore under users/{uid}.pushToken
    let db = Firestore.firestore()
    db.collection("users").document(uid)
      .updateData(["pushToken": fcmToken]) { error in
        if let err = error {
          print("⚠️ Couldn’t save pushToken:", err)
        } else {
          print("✅ pushToken saved.")
        }
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
struct AchillesApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
  @StateObject var authVM = AuthViewModel()
  @State private var photoStatus = PHPhotoLibrary.authorizationStatus()

    var body: some Scene {
      WindowGroup {
        if authVM.user == nil {
          LoginView()
            .environmentObject(authVM)

        } else if !authVM.onboardingComplete {
          OnboardingView()
            .environmentObject(authVM)

        } else if authVM.dailyWelcomeNeeded {
          DailyWelcomeView()
            .environmentObject(authVM)

        } else if photoStatus != .authorized {
          AuthorizationRequiredView(status: photoStatus) {
            PHPhotoLibrary.requestAuthorization { new in
              DispatchQueue.main.async { photoStatus = new }
            }
          }

        } else {
          ContentView()
            .environmentObject(authVM)
        }
      }
    }
  }
