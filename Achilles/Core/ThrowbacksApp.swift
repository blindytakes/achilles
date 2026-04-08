// ThrowbacksApp.swift
//
// Main application file — configures Firebase, manages auth state,
// controls navigation flow, and schedules local notifications.

import SwiftUI
import Firebase
import FirebaseAuth
import FirebaseFirestore
import FirebaseAnalytics
import UserNotifications
import PhotosUI
import GoogleSignIn

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var authVM: AuthViewModel?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        debugLog("AppDelegate: authVM is \(authVM == nil ? "nil" : "wired")")
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
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
    @State private var showCarousel = true
    @State private var carouselSelectedYear: Int? = nil
    @Namespace private var heroNamespace

    private let notificationService = NotificationService()

    init() {
        FirebaseApp.configure()
        Analytics.setAnalyticsCollectionEnabled(true)
        
        Analytics.setUserProperty(
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            forName: "app_version"
        )
        Analytics.setUserProperty(
            Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            forName: "build_number"
        )
        
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: FirebaseApp.app()?.options.clientID ?? "")

        let vm = AuthViewModel()
        _authVM = StateObject(wrappedValue: vm)
        appDelegate.authVM = vm
        
        TelemetryService.shared.initialize()
        TelemetryService.shared.incrementCounter(name: "throwbaks.sessions.total")
        TelemetryService.shared.log("app_launched")
    }
    
    private func updateLastOpened() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = Firestore.firestore().collection("users").document(uid)
        ref.updateData(["lastOpened": FieldValue.serverTimestamp()]) { err in
            if let err = err { debugLog("Failed to update lastOpened: \(err)") }
        }
    }

    private func clearDeliveredNotifications() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().setBadgeCount(0) { error in
            if let error = error { debugLog("Error clearing badge: \(error)") }
        }
    }

    private func shouldPlayIntroVideo() -> Bool {
        if lastIntroVideoPlayDate == 0.0 { return true }
        let lastPlayDate = Date(timeIntervalSince1970: lastIntroVideoPlayDate)
        return !Calendar.current.isDateInToday(lastPlayDate)
    }
  
    private func scheduleDailyMemoryNotifications() async {
        let status = await notificationService.checkAuthorizationStatus()
        
        if status == .notDetermined {
            let granted = await notificationService.requestAuthorization()
            guard granted else { return }
        } else if status != .authorized {
            return
        }
        
        await notificationService.scheduleInactivityReminder(
            daysFromNow: 2, hour: 9, minute: 0,
            yearsWithMemories: photoViewModel.availableYearsAgo
        )
        
        AnalyticsService.shared.logNotificationsScheduled(
            inactivityDays: 2, memoriesCount: photoViewModel.availableYearsAgo.count
        )
    }

    var body: some Scene {
        WindowGroup {
            rootView
                .environmentObject(authVM)
                .environmentObject(photoViewModel)
                .onReceive(
                    NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
                ) { _ in
                    updateLastOpened()
                    TelemetryService.shared.log("app_foreground")
                    AnalyticsService.shared.logAppOpen(source: "foreground_return")
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
                ) { _ in
                    authVM.showMainApp = false
                }
                .background(Color.black)
                .ignoresSafeArea()
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    debugLog("App received URL: \(url)")
                    GIDSignIn.sharedInstance.handle(url)
                    AnalyticsService.shared.logDeepLink(url: url.absoluteString)
                }
        }
        .onChange(of: photoStatus) { newStatus in
            debugLog("Photo-library status: \(newStatus)")
            AnalyticsService.shared.logPhotoPermissionChanged(status: String(describing: newStatus))
        }
    }

    @ViewBuilder
    private var rootView: some View {
        if authVM.isInitializing {
            ZStack {
                Color.black.ignoresSafeArea()
                ProgressView("Loading…").progressViewStyle(CircularProgressViewStyle())
            }
            .onAppear {
                AnalyticsService.shared.logScreenView("app_initializing", screenClass: "LoadingView")
            }
        } else if authVM.user == nil {
            LoginSignupView()
                .onAppear {
                    clearDeliveredNotifications()
                    AnalyticsService.shared.logScreenView("login_signup", screenClass: "LoginSignupView")
                    AnalyticsService.shared.logDailyActiveUser()
                }
        } else {
            if shouldPlayIntroVideo() && !authVM.showMainApp {
                DailyWelcomeView()
                    .onAppear {
                        AnalyticsService.shared.logScreenView("daily_welcome", screenClass: "DailyWelcomeView")
                        AnalyticsService.shared.logOnboardingStart(type: "daily_welcome")
                    }
            } else {
                ZStack {
                    ContentView(initialSelectedYear: $carouselSelectedYear)

                    if showCarousel {
                        YearCarouselView(
                            selectedYear: $carouselSelectedYear,
                            onDismiss: { showCarousel = false }
                        )
                        .transition(.opacity)
                        .onAppear { clearDeliveredNotifications() }
                    }
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: showCarousel)
                .environment(\.heroNamespace, heroNamespace)
                .environment(\.heroYear, carouselSelectedYear)
                .environment(\.showCarousel, showCarousel)
                .onChange(of: showCarousel) { _, newValue in
                    guard !newValue else { return }
                    clearDeliveredNotifications()
                    AnalyticsService.shared.logScreenView("main_content", screenClass: "ContentView")
                    AnalyticsService.shared.logAppOpen(
                        source: "direct",
                        userType: authVM.user?.isAnonymous == true ? "anonymous" : "registered"
                    )
                    AnalyticsService.shared.setUserType(
                        authVM.user?.isAnonymous == true ? "anonymous" : "registered"
                    )
                    Task { await scheduleDailyMemoryNotifications() }
                }
            }
        }
    }
}
