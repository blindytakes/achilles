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
