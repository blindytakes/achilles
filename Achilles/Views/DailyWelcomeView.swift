// DailyWelcomeView.swift
//
// This view provides a daily welcome screen shown to returning users
// when they open the app for the first time each day.
//
// Key features:
// - Displays a friendly welcome message to returning users
// - Provides a simple, clean interface focused on the greeting
// - Includes a prominent button to proceed to the main app
// - Communicates with AuthViewModel to track daily welcome completion
//
// The view serves as a daily touchpoint with users, creating a friendly
// routine and potentially providing a place for daily tips or updates
// before users access the main app content.

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
