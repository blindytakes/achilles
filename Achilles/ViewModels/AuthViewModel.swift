import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
class AuthViewModel: ObservableObject {
    @Published var user: User?
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let auth = Auth.auth()
    private let db   = Firestore.firestore()

    private var authHandle: AuthStateDidChangeListenerHandle?

    init() {
        print("🔌 AuthViewModel init – setting up listener")
        authHandle = auth.addStateDidChangeListener { _, currentUser in
            print("🔑 auth state changed:", currentUser?.uid ?? "nil")
            self.user = currentUser
            guard let _ = currentUser else { return }
            Task {
                do {
                    // 1️⃣ Ensure the user doc exists (creates it if missing)
                    try await self.ensureUserDocument()
                    // 2️⃣ Then safely increment lastLoginAt + sessionCount
                    try await self.updateLastLogin()
                } catch {
                    print("🔥 Firestore error:", error)
                }
            }
        }
    }

    // MARK: - Auth Methods

    func signIn(email: String, password: String) async {
        isLoading = true
        defer { isLoading = false }

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

    func signUp(email: String, password: String, displayName: String) async {
        isLoading = true
        defer { isLoading = false }

        print("🆕 signUp with \(email)")
        do {
            let result = try await auth.createUser(withEmail: email, password: password)
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = displayName
            try await changeRequest.commitChanges()
            self.user = result.user
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
        do {
            try auth.signOut()
            user = nil
            print("✅ signed out")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ signOut error:", error)
        }
    }

    // MARK: - Firestore Helpers

    private func createUserDocument() async throws {
        guard let uid = user?.uid else { return }
        print("📄 [Firestore] createUserDocument() for uid:", uid)
        let data: [String:Any] = [
            "displayName":       user?.displayName ?? "",
            "onboardingComplete": false,
            "yearsViewed":       [],
            "lastLoginAt":       FieldValue.serverTimestamp(),
            "sessionCount":      1,
            "featureFlags":      [:],
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
            "lastLoginAt":    FieldValue.serverTimestamp(),
            "sessionCount":   FieldValue.increment(Int64(1))
        ])
        print("✅ [Firestore] updated lastLoginAt & sessionCount")
    }
}

