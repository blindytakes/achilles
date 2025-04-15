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
            // Background color for letter/pillar boxing
            Color(.systemGray6) // This matches Apple Photos' subtle light gray for letterbox areas

            // Thumbnail image when loaded
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill() // Fill the square frame completely
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped() // Essential to prevent overflow/overlapping
                    .opacity(showImage ? 1 : 0)
                    .animation(.easeIn(duration: 0.3), value: showImage)
                    .onAppear {
                        withAnimation { showImage = true }
                    }
            } else {
                // Loading indicator - Apple's is more subtle
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(Color.gray)
            }

            // Video indicator overlay
            if thumbnail != nil && item.asset.mediaType == .video {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(formattedDuration(item.asset.duration))
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 4)
                            .background(Color.black.opacity(0.3))
                    }
                    .padding(4)
                }
            }
        }
        // Remove forced aspect ratio to allow parent view to control this
        .contentShape(Rectangle())
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
    // Log first to confirm the view appeared
    print("➡️ GridItemView ON APPEAR for Asset ID: \(item.id)")

    // Check *once* if loading is needed
    if thumbnail == nil {
        print("➡️➡️ Thumbnail is nil, calling loadThumbnail() for Asset ID: \(item.id)")
        loadThumbnail() // Call loadThumbnail() *only once*
    } else {
        // Log if the image was already loaded (e.g., view reappeared)
        print("➡️➡️ Thumbnail already exists for Asset ID: \(item.id)")
    }
}
    }

    // Function to load the thumbnail
    private func loadThumbnail() {
        let scale = UIScreen.main.scale
        
        // Get asset's actual dimensions
        let assetWidth = CGFloat(item.asset.pixelWidth)
        let assetHeight = CGFloat(item.asset.pixelHeight)
        
        // Apple Photos uses high-quality thumbnails scaled for the screen
        // Request a larger size than needed to ensure quality
        let targetSize = CGSize(
            width: 150 * scale,  // Apple Photos uses higher resolution thumbnails
            height: 150 * scale
        )
        print("➡️➡️➡️ Calling viewModel.requestImage for Asset ID: \(item.id)")

        // Use PHImageManager's requestImage with proper options
        viewModel.requestImage(for: item.asset, targetSize: targetSize) { image in
            print("⬅️ GridItemView IMAGE RECEIVED for Asset ID: \(item.id). Image is \(image != nil ? "VALID" : "NIL")")

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



