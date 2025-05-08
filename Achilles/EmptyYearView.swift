// EmptyYearView.swift
//
// This view provides feedback when no photos or videos are available for a specific year,
// displaying a friendly empty state message.
//
// Key features:
// - Shows a visual indicator with a "sleeping moon" icon
// - Displays a clear title indicating no memories were found
// - Provides additional context explaining why content might be missing
// - Uses a full-screen layout with centered content
//
// The view is designed to be used as a placeholder in the app when a year
// that would normally show photos has no media content available.

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
