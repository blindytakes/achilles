import SwiftUI

struct ResetPasswordView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.presentationMode) var presentation
    @State private var email       = ""
    @State private var infoMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button("Send Reset Link") {
                    Task {
                        await authVM.resetPassword(email: email)
                        if authVM.errorMessage == nil {
                            infoMessage = "Check your email for reset instructions."
                        }
                    }
                }
                .buttonStyle(.borderedProminent)

                if let msg = infoMessage {
                    Text(msg).foregroundColor(.green)
                }
            }
            .padding()
            .navigationTitle("Reset Password")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { presentation.wrappedValue.dismiss() }
                }
            }
        }
    }
}

