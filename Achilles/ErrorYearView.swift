// Throwbaks/Achilles/Views/ErrorYearView.swift
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

