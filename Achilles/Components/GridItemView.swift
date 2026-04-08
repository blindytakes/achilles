// GridItemView.swift
//
// This view displays individual media items (photos or videos) in a grid layout
// with thumbnail images and media-specific indicators.
//
// Key features:
// - Asynchronously loads and displays thumbnails with a loading placeholder
// - Supports tap interactions with visual feedback (scale animation) and haptic feedback
// - Displays special indicators for different media types:
//   - Video duration badge for video assets
// - Handles image appearance with a smooth fade-in animation
// - Maintains efficient memory usage by loading appropriately sized thumbnails
//
// The view is designed to be used within collection/grid layouts and provides
// a consistent presentation for different types of media assets while
// maintaining good performance through proper image loading techniques.


import SwiftUI
import Photos

struct GridItemView: View {
    @ObservedObject var viewModel: PhotoViewModel
    let item: MediaItem
    var tapAction: (() -> Void)? = nil

    @State private var thumbnail: UIImage?
    @State private var isPressed = false
    @State private var isLoadingThumbnail = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background placeholder
                Color(.systemGray6)

                if let thumbnail = thumbnail {
                    // Thumbnail image
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()

                    // Video duration badge
                    if item.asset.mediaType == .video {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text(formattedDuration(item.asset.duration))
                                    .font(.caption2.bold())
                                    .foregroundColor(.white)
                                    .padding(4)
                                    .background(Color.black.opacity(0.4))
                                    .clipShape(Capsule())
                                    .padding(4)
                            }
                        }
                    }

                } else {
                    // Loading indicator
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.gray)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityLabel(item.asset.mediaType == .video ? "Video, \(formattedDuration(item.asset.duration))" : "Photo")
        .accessibilityAddTraits(.isButton)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isPressed = false
                tapAction?()
            }
        }
        .onAppear {
            if thumbnail == nil && !isLoadingThumbnail { // Only load if not already loaded and not currently loading
                loadThumbnail()
            }
        }
    }

    // MARK: - Helpers
    private func loadThumbnail() {
        isLoadingThumbnail = true
        let scale = UIScreen.main.scale
        // Compute actual cell width from screen width so the request exactly
        // matches what's displayed — no over-fetching on small screens, no
        // under-fetching on large ones (iPhone Plus / Max).
        let screenWidth = UIScreen.main.bounds.width
        let cellPt = floor((screenWidth - 17) / 2) // 12pt h-padding + 5pt grid gap
        let size = CGSize(width: cellPt * scale, height: cellPt * scale)
        viewModel.requestImage(for: item.asset, targetSize: size) { image in
            // Both @State mutations must happen on the main thread.
            DispatchQueue.main.async {
                self.thumbnail = image
                self.isLoadingThumbnail = false
            }
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        guard duration >= 0, duration.isFinite else { return "0:00" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
