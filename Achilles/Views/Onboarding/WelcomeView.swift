// WelcomeView.swift
//
// This view provides the initial welcome experience for the Throwbaks app,
// guiding users through a multi-step onboarding process with photo permissions.

import SwiftUI
import FirebaseAuth
import Photos

// MARK: - Models

/// Represents the onboarding states
enum OnboardingStep: Int, CaseIterable {
    case name = 1
    case authentication
    case photoPermission
    case success
}

/// Groups authentication-related state
struct AuthState {
    var email: String = ""
    var password: String = ""
    var showPassword: Bool = false
    var isLoginMode: Bool = false
}

// MARK: - Main View

struct WelcomeView: View {
    // MARK: - Properties
    
    @EnvironmentObject var authVM: AuthViewModel
    @State private var currentStep: OnboardingStep = .name
    @State private var username = ""
    @State private var authState = AuthState()
    @State private var errorMessage: String? = nil
    @State private var photoAuthStatus: PHAuthorizationStatus = .notDetermined
    @State private var showResetPassword = false
    
    // Brand Colors
    private struct BrandColors {
        static let lightGreen = Color(red: 0.90, green: 0.98, blue: 0.90)
        static let lightYellow = Color(red: 1.0, green: 0.99, blue: 0.91)
        static let darkGreen = Color(red: 0.13, green: 0.55, blue: 0.13)
        static let accentYellow = Color(red: 0.95, green: 0.8, blue: 0.2)
        static let successGreen = Color(red: 0.13, green: 0.7, blue: 0.13)
    }
    
    // MARK: - Computed Properties
    
    private var isStepValid: Bool {
        switch currentStep {
        case .name:
            return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .authentication:
            let emailIsValid = !authState.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let passwordIsValid = !authState.password.isEmpty && authState.password.count >= 6
            return emailIsValid && passwordIsValid
        case .photoPermission:
            return true // Any status is valid
        case .success:
            return true
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [BrandColors.lightGreen, BrandColors.lightYellow]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Card content - improved spacing
            VStack(spacing: 0) {
                // Header
                Text("Welcome to Your Throwbaks")
                    .font(.title2.bold())
                    .foregroundColor(BrandColors.darkGreen)
                    .padding(.top, 20)
                    .padding(.bottom, 10)

                // Step indicator
                StepIndicator(
                    currentStep: currentStep.rawValue,
                    totalSteps: OnboardingStep.allCases.count
                )
                .padding(.vertical, 12)

                // Main content for each step
                Group {
                    switch currentStep {
                        case .name:          nameEntryView
                        case .authentication: credentialsView
                        case .photoPermission: photoPermissionView
                        case .success:       successView
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                // Error message
                if let error = errorMessage ?? authVM.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.subheadline)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }

                // Button area
                if currentStep != .success {
                    if currentStep != .photoPermission {
                        Spacer(minLength: 0) // Push content up, button down
                        
                        Button {
                            continueButtonTapped()
                        } label: {
                            HStack {
                                Text(currentStep == .authentication && authState.isLoginMode
                                    ? "Sign In"
                                    : "Continue")
                                Image(systemName: "arrow.right")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(BrandColors.darkGreen)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .disabled(!isStepValid)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                        .padding(.top, 10)
                    }
                } else {
                    Spacer(minLength: 0)
                    
                    Button {
                        finishButtonTapped()
                    } label: {
                        Text("Relive Your Memories")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(BrandColors.successGreen)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .padding(.top, 10)
                }
            }
            .background(BrandColors.lightGreen)
            .cornerRadius(16)
            .shadow(radius: 5)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .onChange(of: authVM.user) { _, newValue in
            if newValue != nil && currentStep == .authentication {
                goToNextStep()
            }
        }
        .onAppear { initialize() }
    }
    
    // MARK: - Lifecycle Methods
    
    /// Initialize state based on authentication status
    private func initialize() {
        // Check current photo library authorization status
        photoAuthStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        // If user is already authenticated, skip to appropriate step
        if authVM.user != nil {
            // User is authenticated but not fully onboarded
            // Load their name if available
            if let displayName = authVM.user?.displayName, !displayName.isEmpty {
                username = displayName
            }

            // Skip to photo permission step
            currentStep = .photoPermission
        } else {
            // Check if we have any cached credentials (email)
            if let savedEmail = UserDefaults.standard.string(forKey: "lastUsedEmail"), !savedEmail.isEmpty {
                // User has previously started the process
                authState.email = savedEmail
                authState.isLoginMode = true
                currentStep = .authentication
            }
        }
    }
    
    // MARK: - Action Methods
    
    private func continueButtonTapped() {
        errorMessage = nil
        
        switch currentStep {
        case .name:
            if authState.isLoginMode {
                currentStep = .authentication
            } else {
                goToNextStep()
            }
            
        case .authentication:
            // Show loading indicator or disable button
            if authState.isLoginMode {
                Task {
                    do {
                        try await authVM.signIn(email: authState.email, password: authState.password)
                        // Store email for future sessions
                        UserDefaults.standard.set(authState.email, forKey: "lastUsedEmail")
                        // Note: Auto-advances via onChange of authVM.user
                    } catch {
                        // Handle sign-in error
                        errorMessage = error.localizedDescription
                    }
                }
            } else {
                Task {
                    do {
                        try await authVM.signUp(email: authState.email, password: authState.password, displayName: username)
                        // Store email for future sessions
                        UserDefaults.standard.set(authState.email, forKey: "lastUsedEmail")
                        // Note: Auto-advances via onChange of authVM.user
                    } catch {
                        // Handle sign-up error
                        errorMessage = error.localizedDescription
                    }
                }
            }

        case .photoPermission:
            requestPhotoPermission()

        case .success:
            // Should not reach here
            break
        }
    }
    
    private func finishButtonTapped() {
        // Complete onboarding and navigate to main app
        authVM.markOnboardingDone()
    }
    
    private func goToNextStep() {
        // Find the next step
        let allSteps = OnboardingStep.allCases
        if let currentIndex = allSteps.firstIndex(of: currentStep),
           currentIndex + 1 < allSteps.count {
            currentStep = allSteps[currentIndex + 1]
        }
    }
    
    // MARK: - Photo Permission Methods
    
    private func requestPhotoPermission() {
        // First check if we already have permission
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    self.photoAuthStatus = newStatus
                }
            }
        } else {
            // If we already have a determined status, just update our state
            photoAuthStatus = status
            
            // If denied, show alert about settings
            if status == .denied || status == .restricted {
                errorMessage = "Photo access is required for the best experience. You can change this in Settings."
            }
        }
    }
    
    // MARK: - Sub Views
    
    private var nameEntryView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Let's get started!")
                .font(.title3.bold())
                .foregroundColor(BrandColors.darkGreen)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 8) {
                Text("What's Your Name?")
                    .font(.headline)
                    .foregroundColor(.secondary)

                TextField("Enter your name", text: $username)
                    .padding()
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(8)
                    .foregroundColor(.primary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }

            // "Already have an account" option
            Button {
                authState.isLoginMode = true
                currentStep = .authentication
            } label: {
                Text("Already have an account? Sign in")
                    .font(.footnote)
                    .foregroundColor(BrandColors.darkGreen)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            
            Spacer(minLength: 0) // Push content to top
        }
    }

    private var credentialsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(authState.isLoginMode ? "Sign in to your account" : "Create your account")
                .font(.title3.bold())
                .foregroundColor(BrandColors.darkGreen)
                .frame(maxWidth: .infinity, alignment: .center)
            
            if !authState.isLoginMode {
                Text("Hi \(username)! Set up your account credentials")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            
            // Email field
            VStack(alignment: .leading, spacing: 8) {
                Text("Email Address")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    
                HStack {
                    Image(systemName: "envelope")
                        .foregroundColor(.secondary)
                    
                    TextField("your-email@example.com", text: $authState.email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }
                .padding()
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)

            }
            
            // Password field
            VStack(alignment: .leading, spacing: 8) {
                Text("Password")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    
                HStack {
                    Image(systemName: "lock")
                        .foregroundColor(.secondary)
                    
                    Group {
                        if authState.showPassword {
                            TextField("Create a password", text: $authState.password)
                        } else {
                            SecureField("Create a password", text: $authState.password)
                        }
                    }
                    .autocapitalization(.none)
                    
                    Button {
                        authState.showPassword.toggle()
                    } label: {
                        Image(systemName: authState.showPassword ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            
            // Account options with consistent, compact spacing
            VStack(spacing: 12) {
                // Switch between login and signup
                Button {
                    authState.isLoginMode.toggle()
                } label: {
                    Text(authState.isLoginMode ? "Need an account? Sign up" : "Already have an account? Sign in")
                        .font(.footnote)
                        .foregroundColor(BrandColors.darkGreen)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                
                // Forgot password option (only in login mode)
                if authState.isLoginMode {
                    Button {
                        showResetPassword = true
                    } label: {
                        Text("Forgot password?")
                            .font(.footnote)
                            .foregroundColor(BrandColors.darkGreen)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            
            Spacer(minLength: 0) // Push content to top
        }
        .sheet(isPresented: $showResetPassword) {
            ResetPasswordView()
                .environmentObject(authVM)
        }
    }
    
    private var photoPermissionView: some View {
        VStack(spacing: 20) {
            Text("Photo Access")
                .font(.title3.bold())
                .foregroundColor(BrandColors.darkGreen)
                .frame(maxWidth: .infinity, alignment: .center)
            
            Text("Throwbaks needs access to your photo library to help you rediscover your memories.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(BrandColors.darkGreen)
                .padding(.vertical, 10)
            
            if photoAuthStatus == .notDetermined {
                VStack(spacing: 15) {
                    Button {
                        requestPhotoPermission()
                    } label: {
                        HStack {
                            Image(systemName: "photo")
                                .font(.body)
                            Text("Allow Photo Access")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(BrandColors.darkGreen)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    
                    Button {
                        goToNextStep()
                    } label: {
                        Text("Skip for now")
                            .font(.subheadline)
                            .foregroundColor(BrandColors.darkGreen)
                    }
                }
            } else {
                VStack(spacing: 15) {
                    if photoAuthStatus == .authorized || photoAuthStatus == .limited {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(BrandColors.successGreen)
                            
                            Text("Photo access granted!")
                                .foregroundColor(BrandColors.successGreen)
                                .font(.headline)
                            
                            if photoAuthStatus == .limited {
                                Text("You've provided limited access to your photos")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                Button {
                                    if let rootVC = UIApplication.shared.windows.first?.rootViewController {
                                        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: rootVC)
                                    }
                                } label: {
                                    Text("Select more photos")
                                        .font(.footnote)
                                        .foregroundColor(BrandColors.darkGreen)
                                        .padding(.top, 4)
                                }
                            }
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.orange)
                            
                            Text("Photo access denied")
                                .foregroundColor(.orange)
                                .font(.headline)
                            
                            Text("Throwbaks works best with access to your photos")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Button {
                                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(settingsURL)
                                }
                            } label: {
                                Text("Open Settings")
                                    .font(.footnote)
                                    .foregroundColor(BrandColors.darkGreen)
                                    .padding(.top, 4)
                            }
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    Button {
                        goToNextStep()
                    } label: {
                        Text("Continue")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(BrandColors.darkGreen)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
            }
            
            Spacer(minLength: 0) // Push content to top
        }
        .padding(.horizontal, 8)
    }
    
    private var successView: some View {
        VStack(spacing: 20) {
            Text("You're All Set!")
                .font(.title3.bold())
                .foregroundColor(BrandColors.darkGreen)
                .frame(maxWidth: .infinity, alignment: .center)
            
            Image(systemName: "checkmark.circle")
                .font(.system(size: 80))
                .foregroundColor(BrandColors.successGreen)
                .padding(.vertical, 10)
            
            VStack(spacing: 10) {
                Text("Thanks, \(username)! Your account is ready to use.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text("Prepare to rediscover your favorite moments.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 0) // Push content to top
        }
    }
}

// MARK: - Supporting Views

struct StepIndicator: View {
    let currentStep: Int
    let totalSteps: Int
    
    var body: some View {
        HStack(spacing: 8) { // Reduced spacing
            ForEach(1...totalSteps, id: \.self) { step in
                ZStack {
                    // Background circle - smaller
                    Circle()
                        .fill(step <= currentStep ? Color(red: 0.13, green: 0.55, blue: 0.13) : Color.gray.opacity(0.3))
                        .frame(width: 28, height: 28)
                    
                    // Step number
                    if step >= currentStep {
                        Text("\(step)")
                            .font(.caption.bold())
                            .foregroundColor(step <= currentStep ? .white : .gray)
                    }
                    
                    // Checkmark for completed steps
                    if step < currentStep {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                    }
                }
                
                // Connecting line between circles (except after last)
                if step < totalSteps {
                    Rectangle()
                        .fill(step < currentStep ? Color(red: 0.13, green: 0.55, blue: 0.13) : Color.gray.opacity(0.3))
                        .frame(width: 15, height: 2) // Shorter line
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    WelcomeView()
        .environmentObject(AuthViewModel())
}
