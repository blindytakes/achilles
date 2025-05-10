// Achilles/ViewModels/AuthViewModel.swift

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
class AuthViewModel: ObservableObject {
    // MARK: - Published State
    @Published var user: User?
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var onboardingComplete = false
    @Published var dailyWelcomeNeeded = false // Default to false or true based on your logic

    // MARK: - Private Props
    private var listener: ListenerRegistration?
    private let auth = Auth.auth() // Firebase Auth instance
    private let db = Firestore.firestore() // Firestore instance
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var authTask: Task<Void, Error>?

    init() {
        // --- VERY IMPORTANT LOGS - ADD THESE AT THE VERY START OF INIT ---
        let initialCurrentUser = Auth.auth().currentUser // Check Firebase SDK's current user *before* listener
        print("🔌 AuthViewModel: init BEGINNING.")
        print("   Current Auth.auth().currentUser BEFORE listener setup - UID: \(initialCurrentUser?.uid ?? "nil"), Email: \(initialCurrentUser?.email ?? "N/A"), IsAnonymous: \(initialCurrentUser?.isAnonymous.description ?? "N/A")")
        // --- END VERY IMPORTANT LOGS ---

        print("🔌 AuthViewModel: init – Setting up AuthStateDidChangeListener.") // Your original log, good for context

        authHandle = auth.addStateDidChangeListener { [weak self] authObject, firebaseUserObject in
            guard let self = self else {
                print("AuthViewModel Listener: self is nil, returning early.")
                return
            }

            let vmUserBeforeUpdate = self.user // Capture what self.user was in the ViewModel before this listener changed it

            // --- VERY IMPORTANT LISTENER LOGS ---
            print("🔑 AuthViewModel Listener: Auth state DID CHANGE.")
            print("   Listener received authObject.currentUser - UID: \(authObject.currentUser?.uid ?? "nil (from authObject param)") / IsAnonymous: \(authObject.currentUser?.isAnonymous.description ?? "N/A")")
            print("   Listener received firebaseUserObject param - UID: \(firebaseUserObject?.uid ?? "nil (from firebaseUserObject param)") / IsAnonymous: \(firebaseUserObject?.isAnonymous.description ?? "N/A")")
            print("   ViewModel's self.user (BEFORE this update by listener) - UID: \(vmUserBeforeUpdate?.uid ?? "nil") / IsAnonymous: \(vmUserBeforeUpdate?.isAnonymous.description ?? "N/A")")
            // --- END VERY IMPORTANT LISTENER LOGS ---

            self.user = firebaseUserObject // THE CRUCIAL UPDATE TO THE @Published PROPERTY

            print("   ViewModel's self.user (AFTER this update by listener) - UID: \(self.user?.uid ?? "nil") / IsAnonymous: \(self.user?.isAnonymous.description ?? "N/A")")

            if vmUserBeforeUpdate?.uid != self.user?.uid || vmUserBeforeUpdate?.isAnonymous != self.user?.isAnonymous {
                print("   ✅ User state effectively CHANGED in ViewModel. Old UID: \(vmUserBeforeUpdate?.uid ?? "nil"), New UID: \(self.user?.uid ?? "nil").")
            } else {
                print("   ℹ️ User state listener fired, but effective user (UID & anonymous status) in ViewModel did NOT change from its previous state.")
            }

            // Cancel any existing user-specific task first (your existing logic)
            self.authTask?.cancel()
            self.authTask = nil

            // Resubscribe to user document in Firestore (your existing logic)
            // subscribeToUserDoc() should internally handle if self.user is nil or anonymous
            self.subscribeToUserDoc()

            // Guard against nil or anonymous users if your subsequent Firestore tasks should not run for them
            guard let validUserForTasks = self.user, !validUserForTasks.isAnonymous else {
                print("   Listener: Current user in ViewModel is nil or anonymous. Not proceeding with post-authentication Firestore tasks for this user type.")
                return
            }

            print("   Listener: Have a valid, non-anonymous user: \(validUserForTasks.uid). Starting post-authentication Firestore tasks.")
            // Store the reference to the new task (your existing logic)
            self.authTask = Task {
                do {
                    try Task.checkCancellation()
                    print("      Listener Task: Ensuring user document for UID: \(validUserForTasks.uid)")
                    try await self.ensureUserDocument(for: validUserForTasks) // Pass user to ensure context

                    try Task.checkCancellation()
                    print("      Listener Task: Updating last login for UID: \(validUserForTasks.uid)")
                    try await self.updateLastLogin(for: validUserForTasks) // Pass user to ensure context
                    print("      Listener Task: Firestore tasks completed for UID: \(validUserForTasks.uid)")
                } catch is CancellationError {
                    print("      Listener Task: User-specific task was cancelled for UID: \(validUserForTasks.uid).")
                } catch {
                    print("      Listener Task: Firestore error during user-specific task for UID: \(validUserForTasks.uid) - \(error.localizedDescription)")
                }
            }
        }
        print("🔌 AuthViewModel: init COMPLETED. Listener attached.")
    }

    deinit {
        print("🗑️ AuthViewModel: deinit. Removing auth handle and listener.")
        if let handle = authHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
        listener?.remove() // Remove Firestore listener
        authTask?.cancel() // Cancel any ongoing task
    }

    // MARK: - Firestore featureFlags Listener
    func subscribeToUserDoc() {
        listener?.remove() // Remove any existing Firestore listener first
        listener = nil     // Clear the reference

        // Only subscribe if we have a valid, non-anonymous user
        guard let currentUserID = self.user?.uid, self.user?.isAnonymous == false else {
            print("AuthViewModel: subscribeToUserDoc - No valid (non-anonymous) user. Not subscribing to Firestore user document.")
            // Reset local flags that depend on Firestore document if user is nil/anonymous
            DispatchQueue.main.async {
                self.onboardingComplete = false
                self.dailyWelcomeNeeded = true // Or your desired default
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
                    // Potentially clear local state if listener fails critically
                    // self.onboardingComplete = false
                    // self.dailyWelcomeNeeded = true
                    return
                }

                guard let data = snapshot?.data() else {
                    print("   Firestore Listener for UID \(currentUserID): No data in snapshot (document might not exist yet or was deleted).")
                    // This can happen if ensureUserDocument hasn't run yet for a new user,
                    // or if the document was deleted from Firestore.
                    // Reset local state if appropriate.
                    // self.onboardingComplete = false
                    // self.dailyWelcomeNeeded = true
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
                    // If onboardingComplete is missing, decide on a default (likely false)
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
                    // Never shown it before for this user, or field is missing
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
                    // UI update is handled by the Firestore listener reacting to this change
                }
            }
    }

    // MARK: - Auth Methods
    func signIn(email: String, password: String) async -> Bool {
        print("AuthViewModel: Attempting signIn. Email: '\(email)'. Current self.user UID: \(self.user?.uid ?? "nil")")
        isLoading = true; defer { isLoading = false; print("AuthViewModel: signIn task finished.") }
        self.errorMessage = nil // Clear previous errors before new attempt

        do {
            print("   Calling Firebase Auth.auth().signIn...")
            let authResult = try await auth.signIn(withEmail: email, password: password)
            // IMPORTANT: self.user is updated by the AuthStateDidChangeListener.
            // This function returning true only means Firebase reported a successful API call.
            // The listener is the source of truth for self.user.
            print("   ✅ AuthViewModel: Firebase signIn API call SUCCEEDED for email '\(email)'. Result UID: \(authResult.user.uid). Listener should update self.user state.")
            return true
        } catch {
            let nsError = error as NSError
            self.errorMessage = error.localizedDescription // Set for UI
            print("   ❌ AuthViewModel: Firebase signIn API call FAILED for email '\(email)'. Code: \(nsError.code). Error: \(error.localizedDescription)")
            return false
        }
    }

    func signUp(email: String, password: String, displayName: String) async -> Bool {
        print("AuthViewModel: Attempting signUp. Email: '\(email)', Name: '\(displayName)'. Current self.user UID: \(self.user?.uid ?? "nil")")
        isLoading = true; defer { isLoading = false; print("AuthViewModel: signUp task finished.") }
        self.errorMessage = nil // Clear previous errors

        do {
            print("   Calling Firebase Auth.auth().createUser...")
            let authResult = try await auth.createUser(withEmail: email, password: password)
            print("   ✅ AuthViewModel: Firebase createUser API call SUCCEEDED. Result UID: \(authResult.user.uid). Now updating profile...")

            let changeRequest = authResult.user.createProfileChangeRequest()
            changeRequest.displayName = displayName
            try await changeRequest.commitChanges()
            print("   Profile display name updated for UID: \(authResult.user.uid).")
            // self.user is updated by the AuthStateDidChangeListener.
            // ensureUserDocument for a *new* user might need to be called explicitly after this,
            // as the listener might run before this createUserDocument can complete if called from listener too early.
            // However, ensureUserDocument should be idempotent.
            print("   Calling ensureUserDocument after successful signup for UID: \(authResult.user.uid).")
            try await ensureUserDocument(for: authResult.user, isNewUser: true) // Explicitly call for new user
            return true
        } catch {
            let nsError = error as NSError
            self.errorMessage = error.localizedDescription
            print("   ❌ AuthViewModel: Firebase createUser API call FAILED. Code: \(nsError.code). Error: \(error.localizedDescription)")
            return false
        }
    }

    func markOnboardingDone() {
        guard let uid = user?.uid, user?.isAnonymous == false else {
            print("AuthViewModel: markOnboardingDone - No valid user.")
            return
        }
        print("AuthViewModel: markOnboardingDone for UID: \(uid)")
        db.collection("users").document(uid)
            .setData(["featureFlags": ["onboardingComplete": true]], merge: true) { error in // Use setData with merge:true
                if let err = error {
                    print("   ⚠️ Couldn't mark onboarding done for UID \(uid): \(err.localizedDescription)")
                } else {
                    print("   ✅ Onboarding marked done for UID \(uid).")
                    // UI update is handled by the Firestore listener
                }
            }
    }

    func resetPassword(email: String) async {
        print("AuthViewModel: Attempting resetPassword for Email: '\(email)'")
        self.errorMessage = nil
        do {
            try await auth.sendPasswordReset(withEmail: email)
            print("   ✅ Password reset link sent to '\(email)'.")
            // Optionally set a non-error message for UI: self.infoMessage = "Check email..."
        } catch {
            self.errorMessage = error.localizedDescription
            print("   ❌ Password reset FAILED for '\(email)'. Error: \(error.localizedDescription)")
        }
    }

    func signOut() {
        print("AuthViewModel: signOut called. Current user UID before signout: \(user?.uid ?? "nil")")
        authTask?.cancel() // Cancel any user-specific ongoing tasks
        authTask = nil
        // The listener in init() will detect the sign-out and update self.user to nil.
        // It will also trigger subscribeToUserDoc, which will then clear Firestore-dependent state.
        do {
            try auth.signOut()
            print("   ✅ AuthViewModel: Firebase signOut successful. AuthStateDidChangeListener should now set self.user to nil.")
        } catch {
            self.errorMessage = error.localizedDescription
            print("   ❌ AuthViewModel: Firebase signOut FAILED. Error: \(error.localizedDescription)")
        }
    }

    // MARK: - Firestore Helpers
    // Modified ensureUserDocument to accept a User object and a flag for new user
    private func ensureUserDocument(for firebaseUser: User, isNewUser: Bool = false) async throws {
        let uid = firebaseUser.uid
        print("AuthViewModel: ensureUserDocument() for UID: \(uid). Is new user: \(isNewUser)")
        let userDocRef = db.collection("users").document(uid)

        if isNewUser {
            print("   New user scenario. Attempting to create document for UID: \(uid).")
            try await createUserDocument(for: firebaseUser) // Call specific create for new user
        } else {
            let snap = try await userDocRef.getDocument()
            if !snap.exists {
                print("   Existing user scenario, but document NOT found for UID: \(uid). Attempting to create document.")
                try await createUserDocument(for: firebaseUser) // Create if missing, even for existing auth user
            } else {
                print("   Document already exists for UID: \(uid). Skipping create in ensureUserDocument.")
            }
        }
    }

    // Separated createUserDocument for clarity, accepting a User object
    private func createUserDocument(for firebaseUser: User) async throws {
        let uid = firebaseUser.uid
        print("AuthViewModel: createUserDocument() for UID: \(uid)")
        let initialData: [String: Any] = [
            "uid":               uid, // Good to store uid in the doc too
            "email":             firebaseUser.email ?? "", // Store email
            "displayName":       firebaseUser.displayName ?? "",
            "createdAt":         FieldValue.serverTimestamp(), // When the Firestore doc was created
            "lastLoginAt":       FieldValue.serverTimestamp(),
            "sessionCount":      1,
            "featureFlags":      ["onboardingComplete": false], // Default onboarding to false
            "lastDailyWelcomeAt": FieldValue.serverTimestamp(), // Or set to a very old date if welcome should show immediately
            "usageDuration":     0,
            "pushToken":         "", // Will be updated later
            "reminderSchedule":  "",
            "optedIntoEmails":   false
        ]
        try await db.collection("users").document(uid).setData(initialData)
        print("   ✅ [Firestore] Created user document users/\(uid)")
    }

    // Modified updateLastLogin to accept a User object
    private func updateLastLogin(for firebaseUser: User) async throws {
        let uid = firebaseUser.uid
        print("AuthViewModel: updateLastLogin() for UID: \(uid)")
        try await db.collection("users").document(uid).updateData([
            "lastLoginAt": FieldValue.serverTimestamp(),
            "sessionCount": FieldValue.increment(Int64(1))
        ])
        print("   ✅ [Firestore] Updated lastLoginAt & sessionCount for UID: \(uid)")
    }

    func savePushToken(_ token: String) async {
        guard let uid = self.user?.uid, self.user?.isAnonymous == false else {
            print("AuthViewModel: savePushToken - No valid (non-anonymous) user to save token for.")
            return
        }
        print("AuthViewModel: savePushToken for UID: \(uid)")
        do {
            try await db.collection("users").document(uid).updateData(["pushToken": token])
            print("   ✅ PushToken saved in Firestore for UID \(uid).")
        } catch {
            print("   ⚠️ ViewModel failed to save pushToken in Firestore for UID \(uid): \(error.localizedDescription)")
            // Optionally propagate to UI via self.errorMessage if this is critical feedback
        }
    }
}
