import SwiftUI

struct EmptyYearView: View {
    var body: some View {
        VStack(spacing: 15) {
            Spacer() // Pushes content to center vertically

            Image(systemName: "moon.zzz") // Or "photo.on.rectangle.angled", "calendar.badge.exclamationmark"
                .font(.system(size: 60))
                .foregroundColor(.secondary)
                .opacity(0.7)

            Text("No Memories Found")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("There were no photos or videos found for this specific date in this year.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer() // Pushes content to center vertically
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure it fills the space
        .transition(.opacity) // Optional: Fade in/out
    }
}

// MARK: - Preview

struct EmptyYearView_Previews: PreviewProvider {
    static var previews: some View {
        EmptyYearView()
            .padding()
            .previewLayout(.sizeThatFits)
    }
}
