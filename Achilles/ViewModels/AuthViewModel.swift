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
    
    // MARK: - Private Props
    private var listener: ListenerRegistration?     // ← holds our snapshot listener
    private let auth = Auth.auth()
    private let db   = Firestore.firestore()
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var authTask: Task<Void, Error>?  // ← new property to track our async task
    
    init() {
        print("🔌 AuthViewModel init – setting up listener")
        authHandle = auth.addStateDidChangeListener { _, currentUser in
            print("🔑 auth state changed:", currentUser?.uid ?? "nil")
            self.user = currentUser
            
            // Cancel any existing auth task first
            self.authTask?.cancel()
            self.authTask = nil
            
            // start listening for featureFlags.onboardingComplete
            self.subscribeToUserDoc()
            
            guard currentUser != nil else { return }
            
            // Store the reference to the new task
            self.authTask = Task {
                do {
                    // Check for cancellation
                    try Task.checkCancellation()
                    
                    // 1) Create doc if missing
                    try await self.ensureUserDocument()
                    
                    // Check again before next operation
                    try Task.checkCancellation()
                    
                    // 2) bump lastLogin & sessionCount
                    try await self.updateLastLogin()
                } catch {
                    if error is CancellationError {
                        print("🛑 Auth task cancelled")
                    } else {
                        print("🔥 Firestore error:", error)
                    }
                }
            }
        }
    }
    
    // MARK: - Firestore featureFlags Listener
    
    func subscribeToUserDoc() {
        listener?.remove()
        guard let uid = user?.uid else { return }
        
        listener = db.collection("users")
            .document(uid)
            .addSnapshotListener { snapshot, error in
                guard let data = snapshot?.data() else { return }
                
                // — featureFlags.onboardingComplete (already there) —
                if let ff = data["featureFlags"] as? [String:Any],
                   let done = ff["onboardingComplete"] as? Bool {
                    DispatchQueue.main.async { self.onboardingComplete = done }
                }
                
                // — lastDailyWelcomeAt logic —
                if let ts = data["lastDailyWelcomeAt"] as? Timestamp {
                    let lastDate = ts.dateValue()
                    // if it's _not_ today then we need to show it again
                    let needs = !Calendar.current.isDateInToday(lastDate)
                    DispatchQueue.main.async { self.dailyWelcomeNeeded = needs }
                } else {
                    // never shown it before → show it
                    DispatchQueue.main.async { self.dailyWelcomeNeeded = true }
                }
            }
    }
    
    func markDailyWelcomeDone() {
        guard let uid = user?.uid else { return }
        db.collection("users").document(uid)
            .updateData(["lastDailyWelcomeAt": FieldValue.serverTimestamp()]) { error in
                if let err = error {
                    print("⚠️ couldn't mark daily welcome:", err)
                } else {
                    DispatchQueue.main.async {
                        self.dailyWelcomeNeeded = false
                    }
                }
            }
    }
    
    // MARK: - Auth Methods (signIn/signUp/resetPassword/signOut)
    
    func signIn(email: String, password: String) async {
        isLoading = true; defer { isLoading = false }
        print("🔐 signIn with \(email)")
        do {
            let result = try await auth.signIn(withEmail: email, password: password)
            user = result.user
            print("✅ signed in as", result.user.uid)
            try await updateLastLogin()
        } catch {
            errorMessage = error.localizedDescription
            print("❌ signIn error:", error)
        }
    }
    
    /// Call this once the user finishes the welcome/onboarding flow
    func markOnboardingDone() {
        guard let uid = user?.uid else { return }
        db.collection("users")
            .document(uid)
            .updateData(["featureFlags.onboardingComplete": true]) { error in
                if let err = error {
                    print("⚠️ couldn't mark onboarding done:", err)
                } else {
                    // locally flip the flag immediately if you like:
                    DispatchQueue.main.async {
                        self.onboardingComplete = true
                    }
                }
            }
    }
    
    func signUp(email: String, password: String, displayName: String) async {
        isLoading = true; defer { isLoading = false }
        print("🆕 signUp with \(email)")
        do {
            let result = try await auth.createUser(withEmail: email, password: password)
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = displayName
            try await changeRequest.commitChanges()
            user = result.user
            print("✅ created user", result.user.uid, "– now writing Firestore doc")
            try await createUserDocument()
        } catch {
            errorMessage = error.localizedDescription
            print("❌ signUp error:", error)
        }
    }
    
    func resetPassword(email: String) async {
        print("🔄 resetPassword for", email)
        do {
            try await auth.sendPasswordReset(withEmail: email)
            print("✅ reset link sent")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ resetPassword error:", error)
        }
    }
    
    func signOut() {
        print("🔓 signing out")
        
        // Cancel the auth task first
        authTask?.cancel()
        authTask = nil
        
        do {
            try auth.signOut()
            user = nil
            print("✅ signed out")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ signOut error:", error)
        }
    }
    
    // MARK: - Firestore Helpers (user doc lifecycle)
    
    private func createUserDocument() async throws {
        guard let uid = user?.uid else { return }
        print("📄 [Firestore] createUserDocument() for uid:", uid)
        let data: [String:Any] = [
            "displayName":       user?.displayName ?? "",
            "yearsViewed":       [],
            "lastLoginAt":       FieldValue.serverTimestamp(),
            "sessionCount":      1,
            "featureFlags":      ["onboardingComplete": false],
            "lastDailyWelcomeAt": FieldValue.serverTimestamp(),
            "usageDuration":     0,
            "pushToken":         "",
            "reminderSchedule":  "",
            "optedIntoEmails":   false
        ]
        try await db.collection("users").document(uid).setData(data)
        print("✅ [Firestore] wrote users/\(uid)")
    }
    
    private func ensureUserDocument() async throws {
        guard let uid = user?.uid else { return }
        print("🔍 [Firestore] ensureUserDocument() for uid:", uid)
        let snap = try await db.collection("users").document(uid).getDocument()
        if !snap.exists {
            print("🆕 no doc found — creating now")
            try await createUserDocument()
        } else {
            print("🛑 doc already exists, skipping create")
        }
    }
    
    private func updateLastLogin() async throws {
        guard let uid = user?.uid else { return }
        print("⚙️ [Firestore] updateLastLogin() for uid:", uid)
        try await db.collection("users").document(uid).updateData([
            "lastLoginAt":  FieldValue.serverTimestamp(),
            "sessionCount": FieldValue.increment(Int64(1))
        ])
        print("✅ [Firestore] updated lastLoginAt & sessionCount")
    }

    func savePushToken(_ token: String) async {
      guard let uid = user?.uid else { return }
      do {
        try await db.collection("users")
                    .document(uid)
                    .updateData(["pushToken": token])
        print("✅ pushToken saved in ViewModel.")
      } catch {
        print("⚠️ ViewModel failed to save pushToken:", error)
        // optionally propagate to UI:
        errorMessage = error.localizedDescription
      }
    }
}

    
    

