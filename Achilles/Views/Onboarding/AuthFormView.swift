// Achilles/Views/Onboarding/AuthFormView.swift

import SwiftUI

struct AuthFormView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss // To dismiss the sheet if needed

    @Binding var authScreenMode: AuthScreenMode
    @Binding var username: String
    @Binding var email: String
    @Binding var password: String
    @Binding var confirmPassword: String
    @Binding var showPassword: Bool
    @Binding var formErrorMessage: String?

    var onAuthenticationSuccess: () -> Void // Closure to call when auth is successful

    @State private var showResetPasswordSheet = false

    // Using your existing BrandColors, or define locally if preferred
    private struct BrandColors {
        static let darkGreen = Color(red: 0.13, green: 0.55, blue: 0.13)
        static let formBackground = Color(UIColor.systemGray6)
        static let buttonDisabled = Color.gray
        static let buttonEnabled = BrandColors.darkGreen // Or your app's accent color
    }

    private var isFormValid: Bool {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              isValidEmail(email), // Add email format validation
              password.count >= 6 else { // Firebase typically requires 6+ char passwords
            return false
        }
        if authScreenMode == .signUp {
            guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  password == confirmPassword else {
                return false
            }
        }
        return true
    }

    var body: some View {
        NavigationView { // Wrap in NavigationView to get a toolbar for the title and dismiss button
            VStack(spacing: 18) { // Consistent spacing
                if authScreenMode == .signUp {
                    CustomTextField(placeholder: "Username", text: $username, iconName: "person")
                        .textContentType(.username) // For autofill
                }

                CustomTextField(placeholder: "Email", text: $email, iconName: "envelope")
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress) // For autofill
                    .autocapitalization(.none)


                CustomSecureField(placeholder: "Password", text: $password, showPassword: $showPassword, iconName: "lock")
                     .textContentType(authScreenMode == .signUp ? .newPassword : .password) // For autofill


                if authScreenMode == .signUp {
                    CustomSecureField(placeholder: "Confirm Password", text: $confirmPassword, showPassword: $showPassword, iconName: "lock.shield")
                        .textContentType(.newPassword) // For autofill
                }

                if let msg = formErrorMessage {
                    Text(msg)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button(action: handleAuthentication) {
                    Text(authScreenMode == .signUp ? "Create Account" : "Log In")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isFormValid ? BrandColors.buttonEnabled : BrandColors.buttonDisabled)
                        .foregroundColor(.white)
                        .font(.headline)
                        .cornerRadius(10)
                }
                .disabled(!isFormValid)
                .padding(.top, 10)

                if authScreenMode == .signIn {
                    Button("Forgot Password?") {
                        showResetPasswordSheet = true
                    }
                    .font(.footnote)
                    .foregroundColor(BrandColors.darkGreen)
                }

                Button(action: {
                    authScreenMode = (authScreenMode == .signUp) ? .signIn : .signUp
                    // Reset form when switching modes
                    formErrorMessage = nil
                    authVM.errorMessage = nil
                    if authScreenMode == .signIn && !UserDefaults.standard.string(forKey: "lastUsedEmail").isNilOrEmpty {
                        email = UserDefaults.standard.string(forKey: "lastUsedEmail") ?? ""
                    } else {
                        email = "" // Clear email if not pre-filling for sign in
                    }
                    password = "" // Always clear passwords
                    confirmPassword = ""
                    username = ""
                }) {
                    Text(authScreenMode == .signUp ? "Already have an account? Log In" : "Don't have an account? Create Account")
                        .font(.footnote)
                        .foregroundColor(BrandColors.darkGreen)
                }
                .padding(.top, 5)

                Spacer() // Pushes content up
            }
            .padding()
            .background(Color(UIColor.systemBackground).ignoresSafeArea()) // Ensure form background matches system
            .navigationTitle(authScreenMode == .signUp ? "Create Account" : "Log In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(BrandColors.darkGreen)
                }
            }
            .sheet(isPresented: $showResetPasswordSheet) {
                // Assuming ResetPasswordView is already set up to use AuthViewModel
                ResetPasswordView().environmentObject(authVM)
            }
        }
        .accentColor(BrandColors.darkGreen) // Sets the tint for NavigationView elements like the Cancel button
    }

    private func handleAuthentication() {
        print("AuthFormView: handleAuthentication called. Mode: \(authScreenMode)")
        formErrorMessage = nil
        authVM.errorMessage = nil
        print("AuthFormView: Attempting Firebase auth with Email: '\(email)'")
        print("AuthFormView: Password length being sent: \(password.count)")

        Task {
            var authAttemptSuccessful = false
            
            if authScreenMode == .signUp {
                if password != confirmPassword {
                    print("AuthFormView: Passwords do not match.")
                    formErrorMessage = "Passwords do not match."
                    return
                }
                if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    print("AuthFormView: Username is empty.")
                    formErrorMessage = "Username cannot be empty."
                    return
                }
                print("AuthFormView: Calling authVM.signUp with display name: '\(username)'")
                authAttemptSuccessful = await authVM.signUp(email: email, password: password, displayName: username)
            } else { // signIn mode
                print("AuthFormView: Calling authVM.signIn.")
                authAttemptSuccessful = await authVM.signIn(email: email, password: password)
            }

            print("AuthFormView: Firebase call completed. Current attempt success: \(authAttemptSuccessful)")
            
            if authAttemptSuccessful {
                print("AuthFormView: ✅ Auth function reported success.")
                UserDefaults.standard.set(email, forKey: "lastUsedEmail")
                
                // Wait a moment for the auth state to update
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                print("AuthFormView: Calling onAuthenticationSuccess to dismiss sheet.")
                onAuthenticationSuccess()
            } else if let errorFromVM = authVM.errorMessage {
                print("AuthFormView: 🚨 Auth function reported failure! Error: \(errorFromVM)")
                formErrorMessage = errorFromVM
            } else {
                print("AuthFormView: ⚠️ Auth function reported failure, but no error message.")
                formErrorMessage = "An unexpected authentication error occurred."
            }
        }
    }
    // Basic email validation helper
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: email)
    }
}

// Helper Custom TextFields for cleaner AuthFormView
struct CustomTextField: View {
    let placeholder: String
    @Binding var text: String
    var iconName: String? = nil // Optional SFSymbol name

    var body: some View {
        HStack {
            if let iconName = iconName {
                Image(systemName: iconName)
                    .foregroundColor(.gray)
                    .frame(width: 20, alignment: .center) // Consistent icon width
            }
            TextField(placeholder, text: $text)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground)) // More subtle background
        .cornerRadius(10) // Consistent corner radius
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1) // Subtle border
        )
    }
}

struct CustomSecureField: View {
    let placeholder: String
    @Binding var text: String
    @Binding var showPassword: Bool
    var iconName: String? = nil // Optional SFSymbol name


    var body: some View {
        HStack {
            if let iconName = iconName {
                Image(systemName: iconName)
                    .foregroundColor(.gray)
                    .frame(width: 20, alignment: .center)
            }
            Group {
                if showPassword {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            Button {
                showPassword.toggle()
            } label: {
                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

// Helper for UserDefaults check (if not already defined elsewhere)
extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        return self?.isEmpty ?? true
    }
}
