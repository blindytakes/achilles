import SwiftUI
import Photos

struct GridItemView: View {
    // MARK: - Properties
    @ObservedObject var viewModel: PhotoViewModel
    let item: MediaItem
    var tapAction: (() -> Void)? = nil

    // Internal State
    @State private var thumbnail: UIImage? = nil
    @State private var isPressed = false
    @State private var showImage = false // For fade-in animation

    // MARK: - Constants
    private struct Constants {
        // Layout & Style
        static let imageFadeInDuration: Double = 0.3
        static let progressViewScale: CGFloat = 0.7
        static let videoIndicatorVerticalPadding: CGFloat = 2
        static let videoIndicatorHorizontalPadding: CGFloat = 4
        static let videoIndicatorBackgroundOpacity: Double = 0.3
        static let videoIndicatorContainerPadding: CGFloat = 4
        static let minFrameDimension: CGFloat = 0

        // Animation
        static let pressedScale: CGFloat = 0.97
        static let normalScale: CGFloat = 1.0
        static let tapSpringResponse: Double = 0.2
        static let tapSpringDamping: Double = 0.6
        static let tapDispatchDelay: Double = 0.2

        // Image Loading
        static let imageTargetDimension: CGFloat = 300 // For width & height

        // Duration Formatting
        static let secondsPerMinute: Int = 60
        static let minimumValidDuration: TimeInterval = 0

        // Opacity
        static let visibleOpacity: Double = 1.0
        static let hiddenOpacity: Double = 0.0
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            // Background color for letter/pillar boxing if image doesn't fill
            Color(.systemGray6) // System color literal is fine

            // Thumbnail image when loaded
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill() // Ensure it fills the frame
                    .frame(minWidth: Constants.minFrameDimension, maxWidth: .infinity, minHeight: Constants.minFrameDimension, maxHeight: .infinity) // Use constant
                    .clipped()
                    .opacity(showImage ? Constants.visibleOpacity : Constants.hiddenOpacity) // Use constants
                    .animation(.easeIn(duration: Constants.imageFadeInDuration), value: showImage) // Use constant
                    .onAppear {
                        // Only trigger animation on first valid appear
                        if !showImage {
                             withAnimation { showImage = true }
                         }
                    }
            } else {
                // Loading indicator
                ProgressView()
                    .scaleEffect(Constants.progressViewScale) // Use constant
                    .tint(Color.gray) // Color literal is fine
            }

            // Video indicator overlay (only if image is loaded and it's a video)
            if thumbnail != nil && item.asset.mediaType == .video {
                VStack {
                    Spacer() // Push to bottom
                    HStack {
                        Spacer() // Push to right
                        Text(formattedDuration(item.asset.duration))
                            .font(.caption2.bold()) // System font styles are fine
                            .foregroundColor(.white)
                            // Use constants for padding
                            .padding(.vertical, Constants.videoIndicatorVerticalPadding)
                            .padding(.horizontal, Constants.videoIndicatorHorizontalPadding)
                            // Use constant for opacity
                            .background(Color.black.opacity(Constants.videoIndicatorBackgroundOpacity))
                            // Consider adding corner radius? .cornerRadius(4)
                    }
                    // Use constant for padding
                    .padding(Constants.videoIndicatorContainerPadding)
                }
            }
        }
        .contentShape(Rectangle()) // Define tappable area
        // Apply tap animation using constants
        .scaleEffect(isPressed ? Constants.pressedScale : Constants.normalScale)
        .animation(.spring(response: Constants.tapSpringResponse, dampingFraction: Constants.tapSpringDamping), value: isPressed)
        .onTapGesture {
            // Haptic feedback
            UIImpactFeedbackGenerator(style: .light).impactOccurred() // Enum style is fine
            // Trigger pressed state and action after delay
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + Constants.tapDispatchDelay) { // Use constant
                isPressed = false // Reset state
                tapAction?() // Perform action if provided
            }
        }
        .onAppear {
             // Simplified onAppear logic
             print("➡️ GridItemView ON APPEAR for Asset ID: \(item.id)")
             // Load thumbnail only if it's not already loaded
             if thumbnail == nil {
                 print("➡️➡️ Thumbnail is nil, calling loadThumbnail() for Asset ID: \(item.id)")
                 loadThumbnail()
             } else {
                 print("➡️➡️ Thumbnail already exists for Asset ID: \(item.id)")
             }
         }
        // Reset showImage flag if the view disappears and reappears,
        // so the fade-in happens again (optional, depending on desired effect)
         .onDisappear {
             // showImage = false // Uncomment if you want fade-in every time
         }
    }

    // MARK: - Thumbnail Loading
    private func loadThumbnail() {
        let assetIdentifier = item.asset.localIdentifier

        // 1. Check ViewModel cache first
        if let cachedImage = viewModel.cachedImage(for: assetIdentifier) { // Checks non-high-res cache by default
            print("✅ GridItemView using cached thumbnail for Asset ID: \(assetIdentifier)")
            // Update state directly if cached image found
            DispatchQueue.main.async {
                 // Check if view is still relevant for this asset before updating state
                 if self.item.asset.localIdentifier == assetIdentifier {
                     self.thumbnail = cachedImage
                     // self.showImage = true // Optionally trigger show immediately if cached
                 }
            }
            return // Don't proceed to request if already cached
        }

        // 2. If not cached, proceed with the request
        print("➡️➡️➡️ Thumbnail not in cache, calling viewModel.requestImage for Asset ID: \(assetIdentifier)")
        let scale = UIScreen.main.scale // System property is fine
        // Use constant for target dimension
        let targetSize = CGSize(
            width: Constants.imageTargetDimension * scale,
            height: Constants.imageTargetDimension * scale
        )

        // Use the existing requestImage function which handles caching on completion
        viewModel.requestImage(for: item.asset, targetSize: targetSize) { image in
             // Ensure update happens on main thread
            DispatchQueue.main.async {
                 // Check if view is still relevant for this asset before updating state
                 guard self.item.asset.localIdentifier == assetIdentifier else {
                     print("⬅️ GridItemView IMAGE RECEIVED for \(assetIdentifier), but view is no longer relevant.")
                     return
                 }

                 print("⬅️ GridItemView IMAGE RECEIVED for Asset ID: \(assetIdentifier). Image is \(image != nil ? "VALID" : "NIL")")
                 // Only update if the image is valid (might be nil on error)
                 if let validImage = image {
                      self.thumbnail = validImage
                      // Animation will trigger via .onAppear on the Image view itself
                 }
                 // If image is nil after request, the ProgressView remains
            }
        }
    }

    // MARK: - Duration Formatting Helper
    // Helper to format duration (e.g., for video overlay)
    private func formattedDuration(_ duration: TimeInterval) -> String {
         // Use constant for minimum duration check
        guard duration.isFinite && !duration.isNaN && duration >= Constants.minimumValidDuration else { return "0:00" } // Format literal is fine
         // Use constant for seconds per minute
        let totalSeconds = Int(round(duration)) // Round to nearest second
        let minutes = totalSeconds / Constants.secondsPerMinute
        let seconds = totalSeconds % Constants.secondsPerMinute
        return String(format: "%d:%02d", minutes, seconds) // Format string is fine
    }
}
