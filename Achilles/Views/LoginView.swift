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
