// Achilles/Views/Onboarding/LoginSignupView.swift

import SwiftUI
import FirebaseAuth

enum AuthScreenMode {
    case signUp
    case signIn
}

struct LoginSignupView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var showingAuthSheet = false
    @State private var currentAuthScreenMode: AuthScreenMode = .signUp

    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPasswordInForm = false
    @State private var formErrorMessage: String?

    private struct BrandColors {
        static let darkGreen = Color(red: 0.13, green: 0.55, blue: 0.13)
        static let lightGreen = Color(red: 0.4, green: 0.8, blue: 0.4)
        static let mediumGreen = Color(red: 0.3, green: 0.7, blue: 0.3)
    }

    var body: some View {
        ZStack {
            // Background hero section
            LinearGradient(
                gradient: Gradient(colors: [BrandColors.lightGreen, BrandColors.mediumGreen]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Floating emoji icons
            FloatingIconsView()
            
            // Hero content
            VStack {
                Spacer()
                
                VStack(spacing: 8) {
                    Text("Welcome To")
                        .font(.system(size: 48, weight: .black))
                        .foregroundColor(.white.opacity(0.95))
                    
                    Text("Throwbaks")
                        .font(.system(size: 48, weight: .black))
                        .foregroundColor(.white)
                    
                    Text("Your Memories, Rediscovered!")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                Spacer() // Extra space to push content up from bottom sheet
            }
            
            // Bottom sheet
            VStack {
                Spacer()
                
                VStack(spacing: 0) {
                    // Sheet handle
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 40, height: 4)
                        .padding(.top, 12)
                        .padding(.bottom, 20)
                    
                    // Sheet content
                    VStack(alignment: .center, spacing: 24) {
                        VStack(alignment: .center, spacing: 8) {
                            Text("Welcome!")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.primary)
                            
                            Text("Ready To Explore Your Memories?")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(spacing: 12) {
                            // Create Account Button
                            Button {
                                currentAuthScreenMode = .signUp
                                prepareAndShowSheet()
                            } label: {
                                Text("Create Account")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(BrandColors.darkGreen)
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .shadow(color: BrandColors.darkGreen.opacity(0.3), radius: 8, y: 4)
                            }
                            
                            // Sign In Button
                            Button {
                                currentAuthScreenMode = .signIn
                                if let savedEmail = UserDefaults.standard.string(forKey: "lastUsedEmail"), !savedEmail.isEmpty {
                                    email = savedEmail
                                } else {
                                    email = ""
                                }
                                prepareAndShowSheet()
                            } label: {
                                Text("Sign In")
                                    .font(.headline)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(Color(.systemGray6))
                                    .foregroundColor(BrandColors.darkGreen)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                            
                            // Continue as Guest
                            Button {
                                Task {
                                    await authVM.signInAnonymously()
                                }
                            } label: {
                                Text("Continue as Guest")
                                     .font(.caption)
                                     .fontWeight(.medium)
                                     .foregroundColor(.secondary.opacity(0.8))
                                     .underline()
                                     .padding(.top, 8)
                             }
                         }
                     }
                     .padding(.horizontal, 30)
                     .padding(.bottom, 50)
                 }
                 .frame(maxWidth: .infinity)
                 .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                 .shadow(color: .black.opacity(0.1), radius: 20, y: -5)
             }
         }
        .sheet(isPresented: $showingAuthSheet, onDismiss: {
            print("Auth sheet dismissed")
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
                    showingAuthSheet = false
                }
            )
            .environmentObject(authVM)
        }
        .onChange(of: authVM.user) { oldValue, newUser in
            if newUser != nil && showingAuthSheet {
                showingAuthSheet = false
            }
        }
        .onChange(of: authVM.errorMessage) { oldValue, newAuthError in
            if newAuthError != nil {
                formErrorMessage = newAuthError
            }
        }
    }

    private func prepareAndShowSheet() {
        if currentAuthScreenMode == .signUp {
            email = ""
        }
        username = ""
        password = ""
        confirmPassword = ""
        showPasswordInForm = false
        formErrorMessage = nil
        authVM.errorMessage = nil
        showingAuthSheet = true
    }
}

// Floating icons component
struct FloatingIconsView: View {
    @State private var animate1 = false
    @State private var animate2 = false
    @State private var animate3 = false
    
    var body: some View {
        ZStack {
            // Camera icon
            Text("📸")
                .font(.system(size: 32))
                .offset(x: -120, y: animate1 ? -280 : -215)
                .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: animate1)
            
            // Video icon
            Text("🎥")
                .font(.system(size: 28))
                .offset(x: 100, y: animate2 ? -230 : -250)
                .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: animate2)
            
            // Heart icon
            Text("❤️")
                .font(.system(size: 24))
                .offset(x: -10, y: animate3 ? -215 : -240)
                .animation(.easeInOut(duration: 5).repeatForever(autoreverses: true), value: animate3)
        }
        .onAppear {
            animate1 = true
            animate2 = true
            animate3 = true
        }
    }
}
