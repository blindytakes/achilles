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
    // ... (keep existing published properties and private props)
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
        print("🔌 AuthViewModel: init BEGINNING.")
        print("   Current Auth.auth().currentUser BEFORE listener setup - UID: \(initialCurrentUser?.uid ?? "nil"), Email: \(initialCurrentUser?.email ?? "N/A"), IsAnonymous: \(initialCurrentUser?.isAnonymous.description ?? "N/A")")
        
        // Set initial user state immediately if available
        if let currentUser = initialCurrentUser {
            self.user = currentUser
            print("   ℹ️ AuthViewModel: Found existing user on init, setting user property immediately")
            self.subscribeToUserDoc()
            
            if !currentUser.isAnonymous {
                self.authTask = Task {
                    do {
                        print("   AuthViewModel init: Starting initial Firestore tasks for existing user")
                        try await self.ensureUserDocument(for: currentUser)
                        try await self.updateLastLogin(for: currentUser)
                        print("   AuthViewModel init: Initial Firestore tasks completed")
                    } catch {
                        print("   AuthViewModel init: Error in initial Firestore tasks - \(error.localizedDescription)")
                    }
                }
            }
        }

        print("🔌 AuthViewModel: init – Setting up AuthStateDidChangeListener.")

        authHandle = auth.addStateDidChangeListener { [weak self] authObject, firebaseUserObject in
            guard let self = self else {
                print("AuthViewModel Listener: self is nil, returning early.")
                return
            }

            let vmUserBeforeUpdate = self.user

            print("🔑 AuthViewModel Listener: Auth state DID CHANGE.")
            print("   ViewModel's self.user (BEFORE this update by listener) - UID: \(vmUserBeforeUpdate?.uid ?? "nil")")
            
            let userChanged = vmUserBeforeUpdate?.uid != firebaseUserObject?.uid
            
            self.user = firebaseUserObject

            print("   ViewModel's self.user (AFTER this update by listener) - UID: \(self.user?.uid ?? "nil")")

            if userChanged {
                print("   ✅ User state effectively CHANGED in ViewModel. Old UID: \(vmUserBeforeUpdate?.uid ?? "nil"), New UID: \(self.user?.uid ?? "nil").")
                
                self.authTask?.cancel()
                self.authTask = nil
                self.subscribeToUserDoc()

                guard let validUserForTasks = self.user, !validUserForTasks.isAnonymous else {
                    print("   Listener: Current user in ViewModel is nil or anonymous.")
                     // For anonymous users, ensure onboarding is reset if necessary, or handle differently
                    DispatchQueue.main.async {
                        self.onboardingComplete = false // Or load from local storage for anon
                        self.dailyWelcomeNeeded = true // Or load from local storage for anon
                    }
                    return
                }

                print("   Listener: Have a valid, non-anonymous user: \(validUserForTasks.uid).")
                
                self.authTask = Task {
                    do {
                        try Task.checkCancellation()
                        print("      Listener Task: Ensuring user document for UID: \(validUserForTasks.uid)")
                        try await self.ensureUserDocument(for: validUserForTasks)

                        try Task.checkCancellation()
                        print("      Listener Task: Updating last login for UID: \(validUserForTasks.uid)")
                        try await self.updateLastLogin(for: validUserForTasks)
                        print("      Listener Task: Firestore tasks completed")
                    } catch is CancellationError {
                        print("      Listener Task: Cancelled")
                    } catch {
                        print("      Listener Task: Firestore error - \(error.localizedDescription)")
                    }
                }
            } else {
                print("   ℹ️ User state listener fired, but user didn't change.")
            }
        }
        
        print("🔌 AuthViewModel: init COMPLETED. Listener attached.")
        
        // Set initialization complete after a brief delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            self.isInitializing = false
            print("🔌 AuthViewModel: Initialization complete, isInitializing = false")
        }
    }

    deinit {
        print("🗑️ AuthViewModel: deinit")
        if let handle = authHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
        listener?.remove()
        authTask?.cancel()
    }

    func navigateToMainApp() {
        showMainApp = true
    }
    
    func debugPushNotifications() {
        print("🐛 === Push Notification Debug ===")
        
        if let user = self.user {
            print("✅ Current user: \(user.uid) (anonymous: \(user.isAnonymous))")
            
            if user.isAnonymous {
                print("⚠️ User is anonymous - push tokens are not saved for anonymous users")
                return
            }
        } else {
            print("❌ No current user")
            return
        }
        
        guard let uid = user?.uid else { return }
        
        // Check stored token in Firestore
        db.collection("users").document(uid).getDocument { snapshot, error in
            if let error = error {
                print("❌ Error fetching user document: \(error.localizedDescription)")
                return
            }
            
            guard let data = snapshot?.data() else {
                print("❌ No user document found in Firestore")
                return
            }
            
            if let storedToken = data["pushToken"] as? String, !storedToken.isEmpty {
                print("✅ Stored FCM Token: \(storedToken)")
            } else {
                print("❌ No FCM token found in Firestore")
            }
        }
        
        // Get current FCM token
        Messaging.messaging().token { token, error in
            if let error = error {
                print("❌ Error getting current FCM token: \(error.localizedDescription)")
            } else if let token = token {
                print("✅ Current FCM Token: \(token)")
            }
        }
    }
    
    // MARK: - Firestore featureFlags Listener
    func subscribeToUserDoc() {
        listener?.remove()
        listener = nil

        guard let currentUserID = self.user?.uid, self.user?.isAnonymous == false else {
            print("AuthViewModel: subscribeToUserDoc - No valid (non-anonymous) user. Not subscribing to Firestore user document.")
            // For anonymous or nil users, set sensible defaults or load from local storage if you implement that
            DispatchQueue.main.async {
                 // For anonymous users, onboarding is usually considered "complete" immediately,
                 // or you might have a simplified onboarding.
                 // Daily welcome might not apply or could be tracked locally.
                self.onboardingComplete = self.user?.isAnonymous ?? false // if anonymous, they are "onboarded"
                self.dailyWelcomeNeeded = !(self.user?.isAnonymous ?? false) // if anonymous, no daily welcome needed this way
            }
            return
        }

        print("AuthViewModel: subscribeToUserDoc - Subscribing to Firestore for UID: \(currentUserID)")
        listener = db.collection("users")
            .document(currentUserID)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if let err = error {
                    print("   Firestore Listener Error for UID \(currentUserID): \(err.localizedDescription)")
                    return
                }

                guard let data = snapshot?.data() else {
                    print("   Firestore Listener for UID \(currentUserID): No data in snapshot (document might not exist yet or was deleted).")
                     // If document deleted (e.g. during account deletion elsewhere), reset local state
                    self.onboardingComplete = false
                    self.dailyWelcomeNeeded = true
                    return
                }

                print("   Firestore Listener for UID \(currentUserID): Received data update.")
                if let ff = data["featureFlags"] as? [String: Any],
                   let done = ff["onboardingComplete"] as? Bool {
                    if self.onboardingComplete != done {
                        print("      onboardingComplete changed from \(self.onboardingComplete) to \(done)")
                        self.onboardingComplete = done
                    }
                } else {
                     // If field is missing, default to false unless it's a new user setup where it might be true.
                    if self.onboardingComplete != false {
                         print("      onboardingComplete missing from Firestore, defaulting to false.")
                         self.onboardingComplete = false
                    }
                }

                let oldDailyWelcomeNeeded = self.dailyWelcomeNeeded
                if let ts = data["lastDailyWelcomeAt"] as? Timestamp {
                    let lastDate = ts.dateValue()
                    let needs = !Calendar.current.isDateInToday(lastDate)
                    if self.dailyWelcomeNeeded != needs {
                        self.dailyWelcomeNeeded = needs
                    }
                } else {
                     // If field is missing, assume welcome is needed.
                    if self.dailyWelcomeNeeded != true {
                        self.dailyWelcomeNeeded = true
                    }
                }
                if oldDailyWelcomeNeeded != self.dailyWelcomeNeeded {
                     print("      dailyWelcomeNeeded changed from \(oldDailyWelcomeNeeded) to \(self.dailyWelcomeNeeded)")
                }
            }
    }


    func markDailyWelcomeDone() {
        guard let uid = user?.uid, user?.isAnonymous == false else {
            print("AuthViewModel: markDailyWelcomeDone - No valid user to mark for.")
            return
        }
        print("AuthViewModel: markDailyWelcomeDone for UID: \(uid)")
        db.collection("users").document(uid)
            .updateData(["lastDailyWelcomeAt": FieldValue.serverTimestamp()]) { error in
                if let err = error {
                    print("   ⚠️ Couldn't mark daily welcome for UID \(uid): \(err.localizedDescription)")
                } else {
                    print("   ✅ Daily welcome marked for UID \(uid).")
                }
            }
    }

    func markOnboardingDone() {
        guard let uid = user?.uid, user?.isAnonymous == false else {
            print("AuthViewModel: markOnboardingDone - No valid user.")
            return
        }
        print("AuthViewModel: markOnboardingDone for UID: \(uid)")
        db.collection("users").document(uid)
            .setData(["featureFlags": ["onboardingComplete": true]], merge: true) { error in
                if let err = error {
                    print("   ⚠️ Couldn't mark onboarding done for UID \(uid): \(err.localizedDescription)")
                } else {
                    print("   ✅ Onboarding marked done for UID \(uid).")
                }
            }
    }

    // MARK: - Auth Methods
        func signInWithGoogle(presentingViewController: UIViewController) {
            print("AuthViewModel: Attempting signInWithGoogle.")
            isLoading = true
            self.errorMessage = nil

            // 1. Get Client ID for GIDConfiguration
            guard let clientID = FirebaseApp.app()?.options.clientID else {
                self.errorMessage = "Firebase Client ID not found. Check GoogleService-Info.plist."
                self.isLoading = false
                print("   ❌ AuthViewModel: Firebase Client ID not found for Google Sign-In.")
                return
            }
            
            let config = GIDConfiguration(clientID: clientID)
            GIDSignIn.sharedInstance.configuration = config

            // 2. Start the Google Sign-In flow
            GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { [weak self] result, error in
                guard let self = self else { return }

                if let error = error {
                    if (error as NSError).code == GIDSignInError.canceled.rawValue {
                        self.errorMessage = "Google Sign-In was canceled."
                        print("   ⚠️ AuthViewModel: Google Sign-In was canceled by the user.")
                    } else {
                        self.errorMessage = "Google Sign-In failed: \(error.localizedDescription)"
                        print("   ❌ AuthViewModel: Google Sign-In SDK failed. Error: \(error.localizedDescription)")
                    }
                    // Ensure isLoading is set back to false on the main thread
                    DispatchQueue.main.async {
                        self.isLoading = false
                    }
                    return
                }

                guard let googleUser = result?.user,
                      let idToken = googleUser.idToken?.tokenString else {
                    self.errorMessage = "Google Sign-In succeeded but failed to get ID token."
                    print("   ❌ AuthViewModel: Google Sign-In succeeded but ID token was nil.")
                    DispatchQueue.main.async {
                        self.isLoading = false
                    }
                    return
                }
                
                let accessToken = googleUser.accessToken.tokenString
                print("   ✅ AuthViewModel: Google Sign-In SDK SUCCEEDED. Got ID Token. Now creating Firebase credential.")

                // 3. Create Firebase credential
                let credential = GoogleAuthProvider.credential(withIDToken: idToken,
                                                                 accessToken: accessToken)

                // 4. Sign in to Firebase with the Google credential
                Task { @MainActor in // Ensure Firebase sign-in and subsequent logic runs on MainActor
                    do {
                        print("   AuthViewModel: Calling Firebase Auth.auth().signIn(with: credential) for Google user...")
                        let authResult = try await Auth.auth().signIn(with: credential)
                        let firebaseUser = authResult.user
                        let isNewUser = authResult.additionalUserInfo?.isNewUser ?? false
                        
                        print("   ✅ AuthViewModel: Firebase signIn(with: credential) for Google SUCCEEDED. UID: \(firebaseUser.uid), IsNewUser: \(isNewUser)")

                        // For new Google users, ensure their document is created in Firestore.
                        // Your existing authStateDidChangeListener also calls ensureUserDocument,
                        // but calling it here ensures it happens immediately after sign-up logic
                        // and before the listener might fully process if there's any delay.
                        // It's okay if ensureUserDocument is called multiple times as it checks for existence.
                        if !firebaseUser.isAnonymous { // Should not be anonymous if signed in with Google
                            print("   AuthViewModel: Ensuring user document for Google user UID: \(firebaseUser.uid), isNewUser: \(isNewUser)")
                            try await self.ensureUserDocument(for: firebaseUser, isNewUser: isNewUser)
                        }
                        
                        // The AuthStateDidChangeListener in your init() will handle updating self.user,
                        // subscribing to the user document, and other follow-up tasks.
                        self.errorMessage = nil // Clear any previous errors
                        self.isLoading = false
                        print("   AuthViewModel: Google Sign-In and Firebase link successful. Listener will handle further state updates.")

                    } catch {
                        self.errorMessage = "Firebase Sign-In with Google failed: \(error.localizedDescription)"
                        print("   ❌ AuthViewModel: Firebase signIn(with: credential) for Google FAILED. Error: \(error.localizedDescription)")
                        self.isLoading = false
                    }
                }
            }
        }

    private func createUserDocument(for firebaseUser: User) async throws {
        let uid = firebaseUser.uid
        guard !firebaseUser.isAnonymous else {
            print("AuthViewModel: createUserDocument() - User is anonymous (UID: \(uid)). Skipping Firestore document creation.")
            return
        }
        print("AuthViewModel: createUserDocument() for non-anonymous UID: \(uid)")
        let initialData: [String: Any] = [
            "uid": uid,
            "email": firebaseUser.email ?? "",
            "displayName": firebaseUser.displayName ?? "",
            "createdAt": FieldValue.serverTimestamp(),
            "lastLoginAt": FieldValue.serverTimestamp(),
            "sessionCount": 1,
            "featureFlags": ["onboardingComplete": false],
            "lastDailyWelcomeAt": FieldValue.serverTimestamp(),
            // ADD THIS NEW SECTION:
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
        print("   ✅ [Firestore] Created user document users/\(uid)")
    }
    
    func signInAnonymously() async -> Bool {
        isLoading = true
        defer { isLoading = false }
        self.errorMessage = nil
        print("AuthViewModel: Attempting signInAnonymously. Current self.user UID: \(self.user?.uid ?? "nil")")
        do {
            print("   Calling Firebase Auth.auth().signInAnonymously...")
            let authResult = try await auth.signInAnonymously()
            // The authStateDidChangeListener will update self.user.
            // For anonymous users, we typically don't create a Firestore doc
            // unless you have specific anonymous-user data to store.
            // If you do, call ensureUserDocument here.
            // For this example, we assume anonymous users don't get a Firestore doc by default.
            print("   ✅ AuthViewModel: Firebase signInAnonymously API call SUCCEEDED. Result UID: \(authResult.user.uid). Listener should update self.user state.")
            // Potentially set onboardingComplete to true for anonymous users immediately,
            // as they skip the typical onboarding/login form.
            // self.onboardingComplete = true // Handled by listener or direct call if needed
            // self.dailyWelcomeNeeded = false // Anonymous users might not see daily welcome
            return true
        } catch {
            let nsError = error as NSError
            self.errorMessage = error.localizedDescription
            print("   ❌ AuthViewModel: Firebase signInAnonymously API call FAILED. Code: \(nsError.code). Error: \(error.localizedDescription)")
            return false
        }
    }

    // ... (keep existing signIn, signUp, resetPassword, signOut methods)
    func signIn(email: String, password: String) async -> Bool {
        print("AuthViewModel: Attempting signIn. Email: '\(email)'. Current self.user UID: \(self.user?.uid ?? "nil")")
        isLoading = true
        defer {
            isLoading = false
            print("AuthViewModel: signIn task finished.")
        }
        self.errorMessage = nil

        do {
            print("   Calling Firebase Auth.auth().signIn...")
            let authResult = try await auth.signIn(withEmail: email, password: password)
            print("   ✅ AuthViewModel: Firebase signIn API call SUCCEEDED for email '\(email)'. Result UID: \(authResult.user.uid). Listener should update self.user state.")
            return true
        } catch {
            let nsError = error as NSError
            self.errorMessage = error.localizedDescription
            print("   ❌ AuthViewModel: Firebase signIn API call FAILED for email '\(email)'. Code: \(nsError.code). Error: \(error.localizedDescription)")
            return false
        }
    }

    func signUp(email: String, password: String, displayName: String) async -> Bool {
        print("AuthViewModel: Attempting signUp. Email: '\(email)', Name: '\(displayName)'. Current self.user UID: \(self.user?.uid ?? "nil")")
        isLoading = true
        defer {
            isLoading = false
            print("AuthViewModel: signUp task finished.")
        }
        self.errorMessage = nil

        do {
            print("   Calling Firebase Auth.auth().createUser...")
            let authResult = try await auth.createUser(withEmail: email, password: password)
            print("   ✅ AuthViewModel: Firebase createUser API call SUCCEEDED. Result UID: \(authResult.user.uid). Now updating profile...")

            let changeRequest = authResult.user.createProfileChangeRequest()
            changeRequest.displayName = displayName
            try await changeRequest.commitChanges()
            print("   Profile display name updated for UID: \(authResult.user.uid).")
            
            print("   Calling ensureUserDocument after successful signup for UID: \(authResult.user.uid).")
            try await ensureUserDocument(for: authResult.user, isNewUser: true)
            return true
        } catch {
            let nsError = error as NSError
            self.errorMessage = error.localizedDescription
            print("   ❌ AuthViewModel: Firebase createUser API call FAILED. Code: \(nsError.code). Error: \(error.localizedDescription)")
            return false
        }
    }

    func resetPassword(email: String) async {
        print("AuthViewModel: Attempting resetPassword for Email: '\(email)'")
        self.errorMessage = nil
        do {
            try await auth.sendPasswordReset(withEmail: email)
            print("   ✅ Password reset link sent to '\(email)'.")
        } catch {
            self.errorMessage = error.localizedDescription
            print("   ❌ Password reset FAILED for '\(email)'. Error: \(error.localizedDescription)")
        }
    }

    func signOut() {
            print("AuthViewModel: signOut called. Current user UID before signout: \(user?.uid ?? "nil")")
            authTask?.cancel() // Good, you're canceling ongoing tasks
            authTask = nil
            
            // Sign out from Google SDK first (or after, order usually doesn't strictly matter here)
            GIDSignIn.sharedInstance.signOut() // <--- ADD THIS LINE
            print("   AuthViewModel: Called GIDSignIn.sharedInstance.signOut()")

            do {
                try auth.signOut()
                print("   ✅ AuthViewModel: Firebase signOut successful. AuthStateDidChangeListener should now set self.user to nil.")
                // Your existing authStateDidChangeListener will handle self.user = nil
                // and subsequent UI updates.
            } catch {
                self.errorMessage = error.localizedDescription
                print("   ❌ AuthViewModel: Firebase signOut FAILED. Error: \(error.localizedDescription)")
            }
        }


    // << NEW ACCOUNT DELETION METHOD >>
    func deleteAccount() async -> Bool {
        guard let user = Auth.auth().currentUser, !user.isAnonymous else {
            self.errorMessage = "No registered user is currently signed in to delete."
            print("AuthViewModel: deleteAccount - Attempted to delete an anonymous user or no user signed in.")
            return false
        }
        let userId = user.uid
        isLoading = true
        defer { isLoading = false }
        self.errorMessage = nil
        print("AuthViewModel: Attempting to delete account for UID: \(userId)")

        do {
            // 1. Delete Firestore document
            print("   Deleting Firestore document users/\(userId)...")
            try await db.collection("users").document(userId).delete()
            print("   ✅ Successfully deleted Firestore data for user \(userId)")

            // 2. Delete Firebase Auth user
            print("   Deleting Firebase Auth user for UID: \(userId)...")
            try await user.delete()
            print("   ✅ Successfully deleted Firebase Auth user \(userId)")
            // The authStateDidChangeListener will automatically update self.user to nil.
            return true
        } catch {
            self.errorMessage = "Error deleting account: \(error.localizedDescription)"
            print("   ❌ Error deleting account for \(userId): \(error.localizedDescription)")
            // You might need to handle AuthErrorCode.requiresRecentLogin here
            // by prompting the user to re-authenticate.
            return false
        }
    }


    // MARK: - Firestore Helpers
    private func ensureUserDocument(for firebaseUser: User, isNewUser: Bool = false) async throws {
        let uid = firebaseUser.uid
        // If the user is anonymous, do not create a Firestore document by default.
        // You can change this if you have specific needs for anonymous user data.
        guard !firebaseUser.isAnonymous else {
            print("AuthViewModel: ensureUserDocument() - User is anonymous (UID: \(uid)). Skipping Firestore document creation/check.")
            // For anonymous users, you might want to set onboardingComplete to true here if they bypass normal onboarding.
            // self.onboardingComplete = true
            return
        }

        print("AuthViewModel: ensureUserDocument() for non-anonymous UID: \(uid). Is new user: \(isNewUser)")
        let userDocRef = db.collection("users").document(uid)

        if isNewUser {
            print("   New user scenario. Attempting to create document for UID: \(uid).")
            try await createUserDocument(for: firebaseUser)
        } else {
            let snap = try await userDocRef.getDocument()
            if !snap.exists {
                print("   Existing user scenario, but document NOT found for UID: \(uid). Attempting to create document.")
                try await createUserDocument(for: firebaseUser)
            } else {
                print("   Document already exists for UID: \(uid). Skipping create in ensureUserDocument.")
            }
        }
    }

    private func updateLastLogin(for firebaseUser: User) async throws {
        let uid = firebaseUser.uid
        // Ensure we don't try to update documents for anonymous users
        guard !firebaseUser.isAnonymous else {
            print("AuthViewModel: updateLastLogin() - User is anonymous (UID: \(uid)). Skipping Firestore update.")
            return
        }
        print("AuthViewModel: updateLastLogin() for non-anonymous UID: \(uid)")
        try await db.collection("users").document(uid).updateData([
            "lastLoginAt": FieldValue.serverTimestamp(),
            "sessionCount": FieldValue.increment(Int64(1))
        ])
        print("   ✅ [Firestore] Updated lastLoginAt & sessionCount for UID: \(uid)")
    }

    @MainActor
    func savePushToken(_ token: String) async {
        guard let uid = self.user?.uid, self.user?.isAnonymous == false else {
            print("🔕 AuthViewModel: savePushToken - No valid (non-anonymous) user to save token for.")
            return
        }
        
        print("💾 AuthViewModel: Saving FCM token for UID: \(uid)")
        
        do {
            try await db.collection("users").document(uid).setData([
                "pushToken": token,
                "pushTokenUpdatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            print("✅ FCM token successfully saved to Firestore for UID: \(uid)")
        } catch {
            print("❌ Failed to save FCM token to Firestore for UID: \(uid): \(error.localizedDescription)")
        }
    }
}
