import SwiftUI
import Photos // Ensure Photos is imported

struct GridItemView: View {
    @ObservedObject var viewModel: PhotoViewModel
    let item: MediaItem
    var tapAction: (() -> Void)? = nil

    @State private var thumbnail: UIImage? = nil
    @State private var isPressed = false // For tap animation
    @State private var showImage = false // For fade-in animation

    // Define the target size - let's match the LazyVGrid minimum
    private let itemFrameSize: CGFloat = 120

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Background (optional, image should fill this now)
            // Color(.systemGray6) // You could keep this for the ProgressView case

            // Thumbnail image
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipped()
                    .opacity(showImage ? 1 : 0)
                    .animation(.easeIn(duration: 0.3), value: showImage)
                    .onAppear {
                         DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { showImage = true }
                    }
                    .overlay(
                        Group {
                            if item.asset.mediaType == .video {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 20))
                                    Text(formattedDuration(item.asset.duration))
                                        .font(.caption2.bold())
                                }
                                .foregroundColor(.white)
                                .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.black.opacity(0.9),
                                            Color.black.opacity(0.7)
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.4), lineWidth: 1)
                                )
                                .padding(8)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            }
                        }
                    )
            } else {
                // Progress view constrained within the frame
                ZStack { // Use ZStack to add background color behind ProgressView
                    Color(.systemGray6)
                    ProgressView()
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
            }
        }
        // --- Apply frame, cornerRadius, and clipping to the ZStack container ---
        .frame(width: itemFrameSize, height: itemFrameSize) // Constrain the whole cell
        .cornerRadius(8) // Apply rounding
        .clipped() // Clip the container itself
        // Tap gesture and animation (remains the same)
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

    // Function to load the thumbnail (request size logic is important)
    private func loadThumbnail() {
        let scale = UIScreen.main.scale
        // Request an image slightly larger than the frame for quality with scaledToFill
        let targetSize = CGSize(width: itemFrameSize * scale, height: itemFrameSize * scale)

        viewModel.requestImage(for: item.asset, targetSize: targetSize) { image in
            DispatchQueue.main.async {
                self.thumbnail = image
                self.showImage = false // Reset for animation
            }
        }
    }

    // Helper to format duration (remains the same, added robustness)
    func formattedDuration(_ duration: TimeInterval) -> String {
        guard duration.isFinite && !duration.isNaN && duration >= 0 else { return "0:00" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

