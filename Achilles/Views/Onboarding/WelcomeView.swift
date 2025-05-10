// Achilles/Views/Onboarding/WelcomeView.swift

import SwiftUI
import FirebaseAuth

// This enum should be accessible to WelcomeView
enum AuthScreenMode {
    case signUp
    case signIn
}

struct WelcomeView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var showingAuthSheet = false
    @State private var currentAuthScreenMode: AuthScreenMode = .signUp // Default mode for the sheet

    // States for the form fields - these will be passed down to AuthFormView
    // It's good practice to initialize them.
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPasswordInForm = false
    @State private var formErrorMessage: String?

    // BrandColors - kept from your original structure
    private struct BrandColors {
        static let lightGreen = Color(red: 0.90, green: 0.98, blue: 0.90)
        static let lightYellow = Color(red: 1.0, green: 0.99, blue: 0.91)
        static let darkGreen = Color(red: 0.13, green: 0.55, blue: 0.13)
        // static let accentYellow = Color(red: 0.95, green: 0.8, blue: 0.2) // Uncomment if used
        // static let successGreen = Color(red: 0.13, green: 0.7, blue: 0.13) // Uncomment if used
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [BrandColors.lightGreen, BrandColors.lightYellow]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer() // Pushes content towards center

                VStack(spacing: 10) {
                    Text("Welcome to")
                        .font(.title2)
                        .foregroundColor(BrandColors.darkGreen.opacity(0.9))
                    Text("Your Throwbaks")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(BrandColors.darkGreen)
                }
                .padding(.horizontal)

                Text("Rediscover your memories, one day at a time.")
                    .font(.headline)
                    .foregroundColor(BrandColors.darkGreen.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Spacer() // Allows flexible spacing
                Spacer() // Pushes buttons down a bit more from the text

                VStack(spacing: 15) {
                    Button {
                        print("WelcomeView: 'Create Account' button tapped.")
                        currentAuthScreenMode = .signUp
                        prepareAndShowSheet()
                    } label: {
                        Text("Create Account")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(BrandColors.darkGreen)
                            .foregroundColor(.white)
                            .font(.headline)
                            .cornerRadius(12)
                            .shadow(color: BrandColors.darkGreen.opacity(0.3), radius: 5, y: 3)
                    }

                    Button {
                        print("WelcomeView: 'Log In' button tapped.")
                        currentAuthScreenMode = .signIn
                        // Pre-fill email if available for sign-in
                        if let savedEmail = UserDefaults.standard.string(forKey: "lastUsedEmail"), !savedEmail.isEmpty {
                            print("WelcomeView: Pre-filling email for login: \(savedEmail)")
                            email = savedEmail
                        } else {
                            email = "" // Ensure email is clear if no saved email
                        }
                        prepareAndShowSheet()
                    } label: {
                        Text("Log In")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white)
                            .foregroundColor(BrandColors.darkGreen)
                            .font(.headline)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(BrandColors.darkGreen, lineWidth: 1.5)
                            )
                            .shadow(color: Color.black.opacity(0.1), radius: 5, y: 3)
                    }
                }
                .padding(.horizontal, 30)

                Spacer() // Pushes content towards center
            }
        }
        .sheet(isPresented: $showingAuthSheet,
               onDismiss: {
                   print("WelcomeView: Auth sheet was dismissed. showingAuthSheet is now \($showingAuthSheet.wrappedValue). authVM.user UID: \(authVM.user?.uid ?? "nil")")
               }) {
            // Content of the sheet: AuthFormView
            AuthFormView(
                authScreenMode: $currentAuthScreenMode,
                username: $username,
                email: $email,
                password: $password,
                confirmPassword: $confirmPassword,
                showPassword: $showPasswordInForm,
                formErrorMessage: $formErrorMessage,
                onAuthenticationSuccess: {
                    print("WelcomeView: onAuthenticationSuccess callback received from AuthFormView.")
                    showingAuthSheet = false // This will dismiss the sheet
                }
            )
            .environmentObject(authVM) // Pass AuthViewModel to the sheet
        }
        .onChange(of: authVM.user) { oldValue, newUser in
            let oldUID = oldValue?.uid ?? "nil"
            let newUID = newUser?.uid ?? "nil"
            print("WelcomeView: authVM.user changed. From UID: \(oldUID) to New UID: \(newUID). showingAuthSheet: \(showingAuthSheet)")
            if newUser != nil && showingAuthSheet {
                print("WelcomeView: User authenticated while sheet was showing. Attempting to dismiss sheet.")
                showingAuthSheet = false
            }
        }
        .onChange(of: authVM.errorMessage) { oldValue, newAuthError in
            let oldError = oldValue ?? "nil"
            print("WelcomeView: authVM.errorMessage changed. From: '\(oldError)' to New error: '\(newAuthError ?? "nil")'")
            if newAuthError != nil {
                formErrorMessage = newAuthError // Update local error message to be passed to AuthFormView
            }
        }
    }

    private func prepareAndShowSheet() {
        print("WelcomeView: prepareAndShowSheet called. Mode: \(currentAuthScreenMode)")
        // Reset form fields before showing the sheet
        if currentAuthScreenMode == .signUp {
            email = "" // Clear email when switching to sign-up, unless you want to keep it if they toggle
        }
        // Username is cleared regardless, or you might want to keep it if they toggle back and forth
        username = ""
        password = ""
        confirmPassword = ""
        showPasswordInForm = false
        formErrorMessage = nil      // Clear any previous UI errors specific to the form
        authVM.errorMessage = nil // Also clear any global errors from AuthViewModel
        print("WelcomeView: Form fields reset. Setting showingAuthSheet = true")
        showingAuthSheet = true
    }
}
