// LoginView.swift
//
// This view provides the main authentication interface for users to sign into the app,
// with options to create a new account or reset a forgotten password.
//
// Key features:
// - Collects user credentials:
//   - Email address (with appropriate keyboard type)
//   - Password (using secure entry)
// - Validates input fields are non-empty before enabling submission
// - Shows loading indicator during authentication attempts
// - Displays error messages when authentication fails
// - Provides navigation to related authentication flows:
//   - Sign up for new account creation
//   - Password reset for account recovery
//
// The view serves as the central entry point to the app for returning users
// and coordinates with AuthViewModel to handle authentication operations.

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var showSignup = false
    @State private var showReset  = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Welcome Back")
                    .font(.largeTitle).bold()

                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                SecureField("Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                if let error = authVM.errorMessage {
                    Text(error).foregroundColor(.red)
                }

                Button {
                    Task { await authVM.signIn(email: email, password: password) }
                } label: {
                    if authVM.isLoading {
                        ProgressView()
                    } else {
                        Text("Login")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(authVM.isLoading || email.isEmpty || password.isEmpty)

                HStack {
                    Button("Sign Up") { showSignup = true }
                    Spacer()
                    Button("Forgot Password?") { showReset = true }
                }
                .padding(.horizontal)
            }
            .padding()
            .navigationTitle("Login")
            .sheet(isPresented: $showSignup) { SignupView().environmentObject(authVM) }
            .sheet(isPresented: $showReset)  { ResetPasswordView().environmentObject(authVM) }
        }
    }
}
