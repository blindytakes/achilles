import SwiftUI
import Photos

struct GridItemView: View {
    @ObservedObject var viewModel: PhotoViewModel
    let item: MediaItem
    var tapAction: (() -> Void)? = nil

    @State private var thumbnail: UIImage?
    @State private var isPressed = false
    @State private var showImage = false


    private var isLivePhoto: Bool {
      item.asset.mediaSubtypes.contains(.photoLive)
    }

    
    private let itemFrameSize: CGFloat = 200

    var body: some View {
        ZStack {
            // Background placeholder
            Color(.systemGray6)

            if let thumbnail = thumbnail {
                // Thumbnail image
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: itemFrameSize, height: itemFrameSize)
                    .clipped()
                    .opacity(showImage ? 1 : 0)
                    .onAppear {
                        withAnimation(.easeIn(duration: 0.3)) {
                            showImage = true
                        }
                    }

                // Overlays for Live Photo and video duration
                ZStack(alignment: .topLeading) {

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
                }

            } else {
                // Loading indicator
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.gray)
            }
        }
        .frame(width: itemFrameSize, height: itemFrameSize)
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
            if thumbnail == nil {
                loadThumbnail()
            }
        }
    }

    // MARK: - Helpers
    private func loadThumbnail() {
        let assetID = item.asset.localIdentifier
        let scale = UIScreen.main.scale
        let size = CGSize(width: 300 * scale, height: 300 * scale)

        viewModel.requestImage(for: item.asset, targetSize: size) { image in
            DispatchQueue.main.async {
                self.thumbnail = image
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

