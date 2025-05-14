// AuthViewModel.swift
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
    @Published var dailyWelcomeNeeded = false
    @Published var isInitializing = true

    // MARK: - Private Props
    private var listener: ListenerRegistration?
    private let auth = Auth.auth()
    private let db = Firestore.firestore()
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var authTask: Task<Void, Error>?

    // MARK: - Initialization
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

    // MARK: - Firestore featureFlags Listener
    func subscribeToUserDoc() {
        listener?.remove()
        listener = nil

        guard let currentUserID = self.user?.uid, self.user?.isAnonymous == false else {
            print("AuthViewModel: subscribeToUserDoc - No valid (non-anonymous) user. Not subscribing to Firestore user document.")
            DispatchQueue.main.async {
                self.onboardingComplete = false
                self.dailyWelcomeNeeded = true
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
                    if self.dailyWelcomeNeeded != true {
                        self.dailyWelcomeNeeded = true
                    }
                }
                if oldDailyWelcomeNeeded != self.dailyWelcomeNeeded {
                     print("      dailyWelcomeNeeded changed from \(oldDailyWelcomeNeeded) to \(self.dailyWelcomeNeeded)")
                }
            }
    }

    // MARK: - Public Methods
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
        authTask?.cancel()
        authTask = nil
        do {
            try auth.signOut()
            print("   ✅ AuthViewModel: Firebase signOut successful. AuthStateDidChangeListener should now set self.user to nil.")
        } catch {
            self.errorMessage = error.localizedDescription
            print("   ❌ AuthViewModel: Firebase signOut FAILED. Error: \(error.localizedDescription)")
        }
    }

    // MARK: - Firestore Helpers
    private func ensureUserDocument(for firebaseUser: User, isNewUser: Bool = false) async throws {
        let uid = firebaseUser.uid
        print("AuthViewModel: ensureUserDocument() for UID: \(uid). Is new user: \(isNewUser)")
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

    private func createUserDocument(for firebaseUser: User) async throws {
        let uid = firebaseUser.uid
        print("AuthViewModel: createUserDocument() for UID: \(uid)")
        let initialData: [String: Any] = [
            "uid": uid,
            "email": firebaseUser.email ?? "",
            "displayName": firebaseUser.displayName ?? "",
            "createdAt": FieldValue.serverTimestamp(),
            "lastLoginAt": FieldValue.serverTimestamp(),
            "sessionCount": 1,
            "featureFlags": ["onboardingComplete": true],
            "lastDailyWelcomeAt": FieldValue.serverTimestamp(),
            "usageDuration": 0,
            "pushToken": "",
            "reminderSchedule": "",
            "optedIntoEmails": false
        ]
        try await db.collection("users").document(uid).setData(initialData)
        print("   ✅ [Firestore] Created user document users/\(uid)")
    }

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
        }
    }
}
