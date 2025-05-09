// ResetPasswordView.swift
//
// This view provides the user interface for requesting a password reset link,
// allowing users who have forgotten their password to regain access to their account.
//
// Key features:
// - Collects the user's email address with appropriate keyboard configuration
// - Validates that the email field is non-empty before enabling submission
// - Sends password reset request through the AuthViewModel
// - Shows success feedback when the reset link has been sent
// - Provides navigational elements including a title and cancel button
//
// The view uses SwiftUI's environment object pattern to communicate with the
// authentication system and modern environment-based dismissal for navigation.

import SwiftUI

struct ResetPasswordView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss      // modern dismissal
    @State private var email       = ""
    @State private var infoMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .submitLabel(.send)               // show “Send” on keyboard

                Button("Send Reset Link") {
                    Task {
                        await authVM.resetPassword(email: email)
                        if authVM.errorMessage == nil {
                            infoMessage = "Check your email for reset instructions."
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(email.isEmpty)             // ← disabled when the email field is empty

                if let msg = infoMessage {
                    Text(msg)
                        .foregroundColor(.green)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .navigationTitle("Reset Password")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

