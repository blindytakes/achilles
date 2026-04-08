// AuthViewModel.swift
// Achilles/ViewModels/AuthViewModel.swift

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import GoogleSignIn
import FirebaseCore

@MainActor
class AuthViewModel: ObservableObject {
    @Published var user: User?
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var onboardingComplete = false
    @Published var dailyWelcomeNeeded = false
    @Published var isInitializing = true
    @Published var showMainApp = false

    // MARK: - Private Props
    private var listener: ListenerRegistration?
    private let auth = Auth.auth()
    private let db = Firestore.firestore()
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var authTask: Task<Void, Error>?

    init() {
        let initialCurrentUser = Auth.auth().currentUser
        debugLog("AuthViewModel: init beginning. Current user UID: \(initialCurrentUser?.uid ?? "nil")")
        
        if let currentUser = initialCurrentUser {
            self.user = currentUser
            self.subscribeToUserDoc()
            
            if !currentUser.isAnonymous {
                self.authTask = Task {
                    do {
                        try await self.ensureUserDocument(for: currentUser)
                        try await self.updateLastLogin(for: currentUser)
                    } catch {
                        debugLog("AuthViewModel init: Firestore error - \(error.localizedDescription)")
                    }
                }
            }
        }

        authHandle = auth.addStateDidChangeListener { [weak self] authObject, firebaseUserObject in
            guard let self = self else { return }
            let vmUserBeforeUpdate = self.user
            let userChanged = vmUserBeforeUpdate?.uid != firebaseUserObject?.uid
            self.user = firebaseUserObject

            if userChanged {
                debugLog("Auth state changed. Old UID: \(vmUserBeforeUpdate?.uid ?? "nil"), New UID: \(self.user?.uid ?? "nil")")
                self.authTask?.cancel()
                self.authTask = nil
                self.subscribeToUserDoc()

                guard let validUserForTasks = self.user, !validUserForTasks.isAnonymous else {
                    DispatchQueue.main.async {
                        self.onboardingComplete = false
                        self.dailyWelcomeNeeded = true
                    }
                    return
                }

                self.authTask = Task {
                    do {
                        try Task.checkCancellation()
                        try await self.ensureUserDocument(for: validUserForTasks)
                        try Task.checkCancellation()
                        try await self.updateLastLogin(for: validUserForTasks)
                    } catch is CancellationError {
                        debugLog("Auth listener task cancelled")
                    } catch {
                        debugLog("Auth listener Firestore error: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self.isInitializing = false
            debugLog("AuthViewModel: Initialization complete")
        }
    }

    deinit {
        debugLog("AuthViewModel: deinit")
        if let handle = authHandle { Auth.auth().removeStateDidChangeListener(handle) }
        listener?.remove()
        authTask?.cancel()
    }

    func navigateToMainApp() { showMainApp = true }
    
    func debugPushNotifications() {
        debugLog("=== Push Notification Debug ===")
        
        if let user = self.user {
            debugLog("Current user: \(user.uid) (anonymous: \(user.isAnonymous))")
            if user.isAnonymous { debugLog("User is anonymous - push tokens not saved"); return }
        } else {
            debugLog("No current user"); return
        }
        
        guard let uid = user?.uid else { return }
        
        db.collection("users").document(uid).getDocument { snapshot, error in
            if let error = error { debugLog("Error fetching user document: \(error.localizedDescription)"); return }
            guard let data = snapshot?.data() else { debugLog("No user document found"); return }
            if let storedToken = data["pushToken"] as? String, !storedToken.isEmpty {
                debugLog("Stored FCM Token: \(storedToken)")
            } else {
                debugLog("No FCM token found in Firestore")
            }
        }
        
        Messaging.messaging().token { token, error in
            if let error = error { debugLog("Error getting current FCM token: \(error.localizedDescription)") }
            else if let token = token { debugLog("Current FCM Token: \(token)") }
        }
    }
    
    // MARK: - Firestore featureFlags Listener
    func subscribeToUserDoc() {
        listener?.remove()
        listener = nil

        guard let currentUserID = self.user?.uid, self.user?.isAnonymous == false else {
            debugLog("subscribeToUserDoc: No valid non-anonymous user")
            DispatchQueue.main.async {
                self.onboardingComplete = self.user?.isAnonymous ?? false
                self.dailyWelcomeNeeded = !(self.user?.isAnonymous ?? false)
            }
            return
        }

        debugLog("subscribeToUserDoc: Subscribing for UID: \(currentUserID)")
        listener = db.collection("users")
            .document(currentUserID)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if let err = error {
                    debugLog("Firestore listener error for \(currentUserID): \(err.localizedDescription)")
                    return
                }

                guard let data = snapshot?.data() else {
                    self.onboardingComplete = false
                    self.dailyWelcomeNeeded = true
                    return
                }

                if let ff = data["featureFlags"] as? [String: Any],
                   let done = ff["onboardingComplete"] as? Bool {
                    if self.onboardingComplete != done { self.onboardingComplete = done }
                } else {
                    if self.onboardingComplete != false { self.onboardingComplete = false }
                }

                if let ts = data["lastDailyWelcomeAt"] as? Timestamp {
                    let needs = !Calendar.current.isDateInToday(ts.dateValue())
                    if self.dailyWelcomeNeeded != needs { self.dailyWelcomeNeeded = needs }
                } else {
                    if self.dailyWelcomeNeeded != true { self.dailyWelcomeNeeded = true }
                }
            }
    }

    func markDailyWelcomeDone() {
        guard let uid = user?.uid, user?.isAnonymous == false else { return }
        db.collection("users").document(uid)
            .updateData(["lastDailyWelcomeAt": FieldValue.serverTimestamp()]) { error in
                if let err = error { debugLog("Couldn't mark daily welcome: \(err.localizedDescription)") }
            }
    }

    func markOnboardingDone() {
        guard let uid = user?.uid, user?.isAnonymous == false else { return }
        db.collection("users").document(uid)
            .setData(["featureFlags": ["onboardingComplete": true]], merge: true) { error in
                if let err = error { debugLog("Couldn't mark onboarding done: \(err.localizedDescription)") }
            }
    }

    // MARK: - Auth Methods
    func signInWithGoogle(presentingViewController: UIViewController) {
        isLoading = true
        self.errorMessage = nil

        guard let clientID = FirebaseApp.app()?.options.clientID else {
            self.errorMessage = "Firebase Client ID not found. Check GoogleService-Info.plist."
            self.isLoading = false
            return
        }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                if (error as NSError).code == GIDSignInError.canceled.rawValue {
                    self.errorMessage = "Google Sign-In was canceled."
                } else {
                    self.errorMessage = "Google Sign-In failed: \(error.localizedDescription)"
                }
                DispatchQueue.main.async { self.isLoading = false }
                return
            }

            guard let googleUser = result?.user,
                  let idToken = googleUser.idToken?.tokenString else {
                self.errorMessage = "Google Sign-In succeeded but failed to get ID token."
                DispatchQueue.main.async { self.isLoading = false }
                return
            }
            
            let accessToken = googleUser.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)

            Task { @MainActor in
                do {
                    let authResult = try await Auth.auth().signIn(with: credential)
                    let firebaseUser = authResult.user
                    let isNewUser = authResult.additionalUserInfo?.isNewUser ?? false
                    
                    if !firebaseUser.isAnonymous {
                        try await self.ensureUserDocument(for: firebaseUser, isNewUser: isNewUser)
                    }
                    
                    self.errorMessage = nil
                    self.isLoading = false
                } catch {
                    self.errorMessage = "Firebase Sign-In with Google failed: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    private func createUserDocument(for firebaseUser: User) async throws {
        let uid = firebaseUser.uid
        guard !firebaseUser.isAnonymous else { return }
        
        let initialData: [String: Any] = [
            "uid": uid,
            "email": firebaseUser.email ?? "",
            "displayName": firebaseUser.displayName ?? "",
            "createdAt": FieldValue.serverTimestamp(),
            "lastLoginAt": FieldValue.serverTimestamp(),
            "sessionCount": 1,
            "featureFlags": ["onboardingComplete": false],
            "lastDailyWelcomeAt": FieldValue.serverTimestamp(),
            "notificationSettings": [
                "enabled": true,
                "dailyReminderEnabled": true,
                "reEngagementEnabled": true,
                "weeklyDigestEnabled": true,
                "reminderTime": "14:00",
                "timeZone": TimeZone.current.identifier,
                "customMessages": [
                    "Your memories await!",
                    "Discover photos from this day in past years!",
                    "Time for your daily throwback!"
                ],
                "frequency": "daily"
            ],
            "pushToken": ""
        ]
        try await db.collection("users").document(uid).setData(initialData)
        debugLog("Created user document for UID: \(uid)")
    }
    
    func signInAnonymously() async -> Bool {
        isLoading = true
        defer { isLoading = false }
        self.errorMessage = nil
        do {
            let _ = try await auth.signInAnonymously()
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            debugLog("signInAnonymously failed: \(error.localizedDescription)")
            return false
        }
    }

    func signIn(email: String, password: String) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        self.errorMessage = nil
        do {
            let _ = try await auth.signIn(withEmail: email, password: password)
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            debugLog("signIn failed for \(email): \(error.localizedDescription)")
            return false
        }
    }

    func signUp(email: String, password: String, displayName: String) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        self.errorMessage = nil
        do {
            let authResult = try await auth.createUser(withEmail: email, password: password)
            let changeRequest = authResult.user.createProfileChangeRequest()
            changeRequest.displayName = displayName
            try await changeRequest.commitChanges()
            try await ensureUserDocument(for: authResult.user, isNewUser: true)
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            debugLog("signUp failed: \(error.localizedDescription)")
            return false
        }
    }

    func resetPassword(email: String) async {
        self.errorMessage = nil
        do {
            try await auth.sendPasswordReset(withEmail: email)
        } catch {
            self.errorMessage = error.localizedDescription
            debugLog("Password reset failed for \(email): \(error.localizedDescription)")
        }
    }

    func signOut() {
        authTask?.cancel()
        authTask = nil
        GIDSignIn.sharedInstance.signOut()
        do {
            try auth.signOut()
        } catch {
            self.errorMessage = error.localizedDescription
            debugLog("signOut failed: \(error.localizedDescription)")
        }
    }

    func deleteAccount() async -> Bool {
        guard let user = Auth.auth().currentUser, !user.isAnonymous else {
            self.errorMessage = "No registered user is currently signed in to delete."
            return false
        }
        let userId = user.uid
        isLoading = true
        defer { isLoading = false }
        self.errorMessage = nil

        do {
            try await db.collection("users").document(userId).delete()
            try await user.delete()
            return true
        } catch {
            self.errorMessage = "Error deleting account: \(error.localizedDescription)"
            debugLog("deleteAccount failed for \(userId): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Firestore Helpers
    private func ensureUserDocument(for firebaseUser: User, isNewUser: Bool = false) async throws {
        let uid = firebaseUser.uid
        guard !firebaseUser.isAnonymous else { return }

        let userDocRef = db.collection("users").document(uid)
        if isNewUser {
            try await createUserDocument(for: firebaseUser)
        } else {
            let snap = try await userDocRef.getDocument()
            if !snap.exists { try await createUserDocument(for: firebaseUser) }
        }
    }

    private func updateLastLogin(for firebaseUser: User) async throws {
        let uid = firebaseUser.uid
        guard !firebaseUser.isAnonymous else { return }
        try await db.collection("users").document(uid).updateData([
            "lastLoginAt": FieldValue.serverTimestamp(),
            "sessionCount": FieldValue.increment(Int64(1))
        ])
    }

    @MainActor
    func savePushToken(_ token: String) async {
        guard let uid = self.user?.uid, self.user?.isAnonymous == false else { return }
        do {
            try await db.collection("users").document(uid).setData([
                "pushToken": token,
                "pushTokenUpdatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            debugLog("FCM token saved for UID: \(uid)")
        } catch {
            debugLog("Failed to save FCM token: \(error.localizedDescription)")
        }
    }
}
