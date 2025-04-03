import SwiftUI

struct ErrorYearView: View {
    // Pass in the ViewModel to trigger retry
    @ObservedObject var viewModel: PhotoViewModel
    // Pass in the specific year that failed
    let yearsAgo: Int
    // Pass in the error message to display
    let errorMessage: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer() // Pushes content to center vertically

            Image(systemName: "exclamationmark.triangle.fill") // Or "wifi.exclamationmark" etc.
                .font(.system(size: 50))
                .foregroundColor(.orange) // Use a warning color

            Text("Load Failed")
                .font(.title2)

            Text(errorMessage)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry") {
                // Action: Tell the ViewModel to try loading this page again
                print("Retry button tapped for \(yearsAgo) years ago.")
                Task {
                    await viewModel.loadPage(yearsAgo: yearsAgo)
                }
            }
            .buttonStyle(.bordered)
            .padding(.top)

            Spacer() // Pushes content to center vertically
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure it fills the space
        .transition(.opacity) // Optional: Fade in/out
    }
}

// MARK: - Preview

struct ErrorYearView_Previews: PreviewProvider {
    static var previews: some View {
        ErrorYearView(
            viewModel: PhotoViewModel(), // Use a dummy VM for preview
            yearsAgo: 3,
            errorMessage: "Could not connect to the server. Please check your network connection."
        )
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
