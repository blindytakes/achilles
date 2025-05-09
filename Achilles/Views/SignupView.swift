// SignupView.swift
//
// This view provides the user interface for creating a new account in the app,
// collecting name, email, and password information.
//
// Key features:
// - Collects required registration information:
//   - User's display name
//   - Email address (with appropriate keyboard type)
//   - Password (using secure entry)
// - Validates input fields are non-empty before enabling submission
// - Handles account creation through the AuthViewModel
// - Provides navigation with a title and cancel button
// - Automatically dismisses the view upon successful account creation
//
// The view communicates with the AuthViewModel through the environment object
// pattern to execute the signup operation and handle any potential errors.


import SwiftUI

struct SignupView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.presentationMode) var presentation
    @State private var name     = ""
    @State private var email    = ""
    @State private var password = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                TextField("Name", text: $name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                SecureField("Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button("Create Account") {
                    Task {
                        await authVM.signUp(
                            email: email,
                            password: password,
                            displayName: name
                        )
                        if authVM.errorMessage == nil {
                            presentation.wrappedValue.dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || email.isEmpty || password.isEmpty)
            }
            .padding()
            .navigationTitle("Sign Up")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { presentation.wrappedValue.dismiss() }
                }
            }
        }
    }
}

