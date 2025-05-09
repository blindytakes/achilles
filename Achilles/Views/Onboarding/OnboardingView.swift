// OnboardingView.swift
//
// This view provides a welcome onboarding experience for new users,
// introducing them to the app's key features after successful account creation.
//
// Key features:
// - Displays a welcome message with the app name
// - Presents introductory information about the app
// - Includes a prominent button to complete the onboarding process
// - Communicates with AuthViewModel to track onboarding completion status
//
// The view is designed to be shown only once after initial account creation
// or login, helping new users understand the app's functionality before
// proceeding to the main content.

import SwiftUI

struct OnboardingView: View {
  @EnvironmentObject var authVM: AuthViewModel

  var body: some View {
    VStack(spacing: 24) {
      Text("Welcome to Achilles!")
        .font(.largeTitle)
      Text("Here’s a quick tour to get you started…")
        .multilineTextAlignment(.center)
      // …your slides / buttons / explainer UI…

      Button("Got it, let’s go!") {
        authVM.markOnboardingDone()
      }
      .buttonStyle(.borderedProminent)
    }
    .padding()
  }
}

struct OnboardingView_Previews: PreviewProvider {
  static var previews: some View {
    OnboardingView()
      .environmentObject(AuthViewModel())
  }
}
