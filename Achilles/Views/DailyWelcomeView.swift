import SwiftUI

struct DailyWelcomeView: View {
  @EnvironmentObject var authVM: AuthViewModel

  var body: some View {
    VStack(spacing: 24) {
      Text("Welcome back!")
        .font(.largeTitle)
      Text("Great to see you again today.")
      Button("Let’s go!") {
        authVM.markDailyWelcomeDone()
      }
      .buttonStyle(.borderedProminent)
    }
    .padding()
  }
}
