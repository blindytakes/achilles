// ErrorYearView.swift
//
// This view provides error feedback when loading photos for a specific year fails,
// displaying an error message and offering a retry option.
//
// Key features:
// - Shows a visual error indicator with an exclamation triangle icon
// - Displays both a generic error title and the specific error message
// - Provides a retry button that triggers the viewModel to attempt reloading
// - Uses a full-screen layout to replace the normal content view
//
// The view maintains a reference to both the viewModel (for retry functionality)
// and the specific year that failed to load, enabling targeted reload attempts.


import SwiftUI
import Photos

struct ErrorYearView: View {

    // <<< CHANGE: Observe PhotoViewModel instead of YearLoader >>>
    @ObservedObject var viewModel: PhotoViewModel
    let yearsAgo: Int // Keep for context
    let errorMessage: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.orange)

            Text("Load Failed")
                .font(.title2)

            Text(errorMessage)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry") {
                // <<< CHANGE: Call retryLoad on the ViewModel >>>
                print("🔁 Retry button tapped for \(yearsAgo) years ago.")
                viewModel.retryLoad(yearsAgo: yearsAgo) // Use ViewModel's retry
            }
            .buttonStyle(.bordered)
            .padding(.top)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }
}

