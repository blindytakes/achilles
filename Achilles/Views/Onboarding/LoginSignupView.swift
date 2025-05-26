// Achilles/Views/Onboarding/LoginSignupView.swift

import SwiftUI
import FirebaseAuth

// This enum should be accessible to WelcomeView
enum AuthScreenMode {
    case signUp
    case signIn
}

struct LoginSignupView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var showingAuthSheet = false
    @State private var currentAuthScreenMode: AuthScreenMode = .signUp // Default mode for the sheet

    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPasswordInForm = false
    @State private var formErrorMessage: String?

    private struct BrandColors {
        static let lightGreen = Color(red: 0.90, green: 0.98, blue: 0.90)
        static let lightYellow = Color(red: 1.0, green: 0.99, blue: 0.91)
        static let darkGreen = Color(red: 0.13, green: 0.55, blue: 0.13)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [BrandColors.lightGreen, BrandColors.lightYellow]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()

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

                Spacer()
                Spacer()

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
                        if let savedEmail = UserDefaults.standard.string(forKey: "lastUsedEmail"), !savedEmail.isEmpty {
                            print("WelcomeView: Pre-filling email for login: \(savedEmail)")
                            email = savedEmail
                        } else {
                            email = ""
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
                    
                    Spacer()
                        .frame(height: 80)

                    // << NEW CONTINUE AS GUEST BUTTON >>
                    Button {
                        print("WelcomeView: 'Continue as Guest' button tapped.")
                        Task {
                            await authVM.signInAnonymously()
                            // The authVM.user change will be picked up by ThrowbaksApp
                            // and navigate to the main content if successful.
                            // No sheet is shown for guest login.
                        }
                    } label: {
                        Text("Continue as Guest")
                            .font(.subheadline) // Smaller font
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10) // Smaller vertical padding
                            .background(Color.gray.opacity(0.1)) // Even more subtle background
                            .foregroundColor(BrandColors.darkGreen.opacity(0.7)) // More muted color
                            .cornerRadius(8) // Smaller corner radius
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(BrandColors.darkGreen.opacity(0.3), lineWidth: 0.5)
                            )
                                                }
                                            }
                                            .padding(.horizontal, 30)

                                            Spacer()
                                        }
                                    }
        
        .sheet(isPresented: $showingAuthSheet,
               onDismiss: {
                   print("WelcomeView: Auth sheet was dismissed. showingAuthSheet is now \($showingAuthSheet.wrappedValue). authVM.user UID: \(authVM.user?.uid ?? "nil")")
               }) {
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
                    showingAuthSheet = false
                }
            )
            .environmentObject(authVM)
        }
        .onChange(of: authVM.user) { oldValue, newUser in
            let oldUID = oldValue?.uid ?? "nil"
            let newUID = newUser?.uid ?? "nil"
            print("WelcomeView: authVM.user changed. From UID: \(oldUID) to New UID: \(newUID). showingAuthSheet: \(showingAuthSheet)")
            // This will dismiss the sheet if user signs up/in successfully *while the sheet is open*.
            // For anonymous login, the sheet isn't shown, so this part is less critical for that flow.
            if newUser != nil && showingAuthSheet {
                print("WelcomeView: User authenticated while sheet was showing. Attempting to dismiss sheet.")
                showingAuthSheet = false
            }
        }
        .onChange(of: authVM.errorMessage) { oldValue, newAuthError in
            let oldError = oldValue ?? "nil"
            print("WelcomeView: authVM.errorMessage changed. From: '\(oldError)' to New error: '\(newAuthError ?? "nil")'")
            if newAuthError != nil {
                formErrorMessage = newAuthError
            }
        }
    }

    private func prepareAndShowSheet() {
        print("WelcomeView: prepareAndShowSheet called. Mode: \(currentAuthScreenMode)")
        print("WelcomeView: Current authVM.user: \(authVM.user?.uid ?? "nil")")
        if currentAuthScreenMode == .signUp {
            email = ""
        }
        username = ""
        password = ""
        confirmPassword = ""
        showPasswordInForm = false
        formErrorMessage = nil
        authVM.errorMessage = nil
        print("WelcomeView: Form fields reset. Setting showingAuthSheet = true")
        showingAuthSheet = true
    }
}
