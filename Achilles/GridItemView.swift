import SwiftUI
import Photos

struct GridItemView: View {
    @ObservedObject var viewModel: PhotoViewModel
    let item: MediaItem
    var tapAction: (() -> Void)? = nil

    @State private var thumbnail: UIImage? = nil
    @State private var isPressed = false
    @State private var showImage = false

    private let itemFrameSize: CGFloat = 200 // Higher quality request

    var body: some View {
        ZStack {
            // Background color for loading state AND letter/pillar boxing
            Color(.systemGray6) // This will show in empty areas for non-square images

            // Thumbnail image when loaded
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .clipped()
                    .opacity(showImage ? 1 : 0)
                    .animation(.easeIn(duration: 0.3), value: showImage)
                    .onAppear {
                        withAnimation { showImage = true }
                    }
            } else {
                // Loading indicator
                ProgressView()
            }

            // Video indicator overlay (positioning might need slight adjustment if desired)
            if thumbnail != nil && item.asset.mediaType == .video {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 18))
                            Text(formattedDuration(item.asset.duration))
                                .font(.caption2.bold())
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(12)
                        .padding(8)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit) // Keep forcing the ZStack container to be square
        .contentShape(Rectangle()) // Define the tappable area
        // --- Rest of your modifiers for animation, tap gesture, etc. ---
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
            if thumbnail == nil {
                loadThumbnail()
            }
        }
    }

    // Function to load the thumbnail
    private func loadThumbnail() {
        let scale = UIScreen.main.scale
        let targetSize = CGSize(width: itemFrameSize * scale, height: itemFrameSize * scale)

        viewModel.requestImage(for: item.asset, targetSize: targetSize) { image in
            DispatchQueue.main.async {
                self.thumbnail = image
            }
        }
    }

    // Helper to format duration
    func formattedDuration(_ duration: TimeInterval) -> String {
        guard duration.isFinite && !duration.isNaN && duration >= 0 else { return "0:00" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
