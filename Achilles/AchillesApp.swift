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
struct AchillesApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @StateObject private var authVM: AuthViewModel
  @State private var photoStatus = PHPhotoLibrary.authorizationStatus()
  
  init() {
    // 1) Configure Firebase
    FirebaseApp.configure()
    
    // 2) Initialize AuthViewModel
    _authVM = StateObject(wrappedValue: AuthViewModel())
    
    // 3) Connect AppDelegate to AuthViewModel (this will work because we use _authVM directly)
    appDelegate.authVM = authVM
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
      LoginView()
    } else if !authVM.onboardingComplete {
      OnboardingView()
    } else if authVM.dailyWelcomeNeeded {
      DailyWelcomeView()
    } else if photoStatus != .authorized {
      AuthorizationRequiredView(status: photoStatus) {
        PHPhotoLibrary.requestAuthorization { new in
          DispatchQueue.main.async { photoStatus = new }
        }
      }
    } else {
      ContentView()
    }
  }
}
