import SwiftUI
import Photos
import AVKit
import UIKit

// MARK: - State Enum Definition
fileprivate enum DetailViewState {
    case loading
    case error(String)
    case image(displayImage: UIImage)
    case unsupported // Covers video/audio/unknown handled by main switch
}

// MARK: - ItemDisplayView

struct ItemDisplayView: View {
    // MARK: - Properties
    @ObservedObject var viewModel: PhotoViewModel
    let item: MediaItem
    let player: AVPlayer? // Passed down from MediaDetailView
    @Binding var showInfoPanel: Bool

    // Internal State
    @State private var viewState: DetailViewState = .loading
    @State private var controlsHidden: Bool = false
    @State private var zoomScale: CGFloat = 1.0 // Used by ZoomableScrollView
    @Environment(\.dismiss) private var dismiss
    @State private var currentRequestID: PHImageRequestID?

    // MARK: - Constants
    // Layout & Frame
    private let locationButtonBottomPadding: CGFloat = 40
    private let locationButtonSize: CGFloat = 60
    private let locationButtonCornerRadius: CGFloat = 12
    private let locationButtonStrokeWidth: CGFloat = 1
    private let mapIconWidth: CGFloat = 32
    private let mapIconHeight: CGFloat = 24
    private let mapIconCornerRadius: CGFloat = 6
    private let mapPinIconSize: CGFloat = 26
    private let mapPinIconYOffset: CGFloat = -2
    private let mapLabelFontSize: CGFloat = 12
    private let mapLabelVStackSpacing: CGFloat = 4 // Spacing in location button
    private let locationPanelHorizontalMargin: CGFloat = 12
    private let locationPanelHeightFactor: CGFloat = 0.65 // % of geometry height
    private let locationPanelMaxHeight: CGFloat = 400
    private let locationPanelPositionXFactor: CGFloat = 0.5 // Center X
    private let locationPanelPositionYFactor: CGFloat = 0.45
    private let errorVStackSpacing: CGFloat = 8
    private let zoomableImageYOffset: CGFloat = -20

    // Animation & Timing
    private let locationButtonFadeDuration: Double = 0.25
    private let panelSpringResponse: Double = 0.4
    private let panelSpringDamping: Double = 0.75

    // Style & Visuals
    private let locationButtonBackgroundOpacity: Double = 0.85
    private let locationButtonShadowOpacity: Double = 0.25
    private let locationButtonShadowRadius: CGFloat = 4
    private let locationButtonShadowYOffset: CGFloat = 2
    private let locationButtonStrokeOpacity: Double = 0.3
    private let mapIconFillOpacity: Double = 0.2
    private let mapPinShadowOpacity: Double = 0.25
    private let mapPinShadowRadius: CGFloat = 1
    private let mapPinShadowYOffset: CGFloat = 1
    private let progressViewScale: CGFloat = 1.5
    private let hiddenOpacity: Double = 0.0
    private let visibleOpacity: Double = 1.0

    // Z-Indexes
    private let contentZIndex: Double = 0
    private let locationButtonZIndex: Double = 1
    private let locationPanelZIndex: Double = 2

    // MARK: - Body
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Main content area (Image, Video, Loading, Error)
                mainContentSwitchView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle()) // Ensure entire area is tappable for ZoomableScrollView
                    .zIndex(contentZIndex) // Base layer

                // Location button overlay (only if location exists and panel is hidden)
                if item.asset.location != nil && !showInfoPanel {
                    locationButton
                        .opacity(controlsHidden ? hiddenOpacity : visibleOpacity) // Use constants
                        .animation(.easeInOut(duration: locationButtonFadeDuration), value: controlsHidden) // Use constant
                        .zIndex(locationButtonZIndex) // Above content
                }

                // Location info panel overlay (only if location exists and panel is shown)
                if showInfoPanel, let location = item.asset.location { // Ensure location exists
                    LocationInfoPanelView(asset: item.asset)
                        // Size and position the panel relative to the screen
                        .frame(width: geometry.size.width - locationPanelHorizontalMargin * 2) // Use margin constant
                        .frame(maxHeight: min(geometry.size.height * locationPanelHeightFactor, locationPanelMaxHeight)) // Use constants
                        .position(x: geometry.size.width * locationPanelPositionXFactor, y: geometry.size.height * locationPanelPositionYFactor) // Use constants
                        .transition(.opacity.combined(with: .offset(y: geometry.size.height * 0.1))) // Add offset transition
                        .zIndex(locationPanelZIndex) // Above location button
                }
            }
            .background(Color.black) // Ensure background for entire ZStack
            .id(item.id) // Force redraw when item changes
            .ignoresSafeArea(.all, edges: .all) // Extend to screen edges
        }
        .task { await loadImageOnlyIfNeeded() } // Load image when view appears/task starts
        .onChange(of: item.id) { _, newItemId in // Use correct onChange signature if needed
            // Reset view state when the item changes
             if item.asset.mediaType == .image {
                 viewState = .loading
             } else {
                 // Video/Audio is handled directly by the player state passed in
                 // Set unsupported only if it's truly not image/video/audio?
                 // Or rely on mainContentSwitchView to handle it.
                 // Let's just reset image-specific state.
                 viewState = (item.asset.mediaType == .image) ? .loading : .unsupported
             }
             // Reset panel state when item changes
             showInfoPanel = false
             controlsHidden = false // Also reset controls visibility
             zoomScale = 1.0 // Reset zoom scale
        }
        .onAppear {
             // Add observers for notifications
             setupNotificationObservers()
        }
        .onDisappear {
             // Cancel any ongoing image requests and remove observers
             cancelImageRequest()
             removeNotificationObservers()
        }
    }

    // MARK: - Location Button View
    private var locationButton: some View {
        Button {
            // Show panel with spring animation
            withAnimation(.spring(response: panelSpringResponse, dampingFraction: panelSpringDamping)) { // Use constants
                showInfoPanel = true
            }
            // Provide haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

        } label: {
            ZStack {
                // Background with subtle material effect
                RoundedRectangle(cornerRadius: locationButtonCornerRadius) // Use constant
                    .fill(Color(.systemBackground).opacity(locationButtonBackgroundOpacity)) // Use constant
                    .shadow(color: .black.opacity(locationButtonShadowOpacity), radius: locationButtonShadowRadius, x: 0, y: locationButtonShadowYOffset) // Use constants
                    .frame(width: locationButtonSize, height: locationButtonSize) // Use constant
                    .overlay(
                        RoundedRectangle(cornerRadius: locationButtonCornerRadius) // Use constant
                            .stroke(Color.white.opacity(locationButtonStrokeOpacity), lineWidth: locationButtonStrokeWidth) // Use constants
                    )

                // Map icon and label
                VStack(spacing: mapLabelVStackSpacing) { // Use constant
                    ZStack {
                        // Stylized map background shape
                        RoundedRectangle(cornerRadius: mapIconCornerRadius) // Use constant
                            .fill(Color.blue.opacity(mapIconFillOpacity)) // Use constant
                            .frame(width: mapIconWidth, height: mapIconHeight) // Use constants

                        // Pin icon overlay
                        Image(systemName: "mappin.circle.fill") // System name is fine as literal
                            .font(.system(size: mapPinIconSize, weight: .semibold)) // Use constant
                            .foregroundColor(.red) // Color literal is fine
                            .shadow(color: .black.opacity(mapPinShadowOpacity), radius: mapPinShadowRadius, x: 0, y: mapPinShadowYOffset) // Use constants
                            .offset(y: mapPinIconYOffset) // Use constant
                    }

                    Text("Map") // String literal is fine
                        .font(.system(size: mapLabelFontSize, weight: .medium)) // Use constant
                        .foregroundColor(.primary) // System color is fine
                }
            }
        }
        .padding(.bottom, locationButtonBottomPadding) // Use constant
    }

    // MARK: - Main Content Switching View
    @ViewBuilder private var mainContentSwitchView: some View {
        switch item.asset.mediaType {
        case .image:
            // Handle different states for image loading
            switch viewState {
            case .loading:
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(progressViewScale) // Use constant
            case .error(let message):
                // Display error state
                VStack(spacing: errorVStackSpacing) { // Use constant
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.largeTitle) // System font style is fine
                    Text("Error Loading Media")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal) // Default padding is okay here
                }
            case .image(let displayImage):
                // Display the loaded image in the zoomable view
                ZoomableScrollView(
                    showInfoPanel: $showInfoPanel,
                    controlsHidden: $controlsHidden,
                    zoomScale: $zoomScale,
                    dismissAction: { dismiss() }
                ) {
                    Image(uiImage: displayImage)
                        .resizable()
                        .interpolation(.high) // Enum value is fine
                        .antialiased(true) // Boolean literal is fine
                        .aspectRatio(contentMode: .fit) // Enum value is fine
                        .frame(maxWidth: .infinity, maxHeight: .infinity) // System constants are fine
                        .background(Color.black)
                        .offset(y: zoomableImageYOffset) // Use constant
                }
            case .unsupported: // Should ideally not happen if mediaType is .image
                Text("Internal Error: Unsupported image state.")
                    .foregroundColor(.secondary)
            }
        case .video:
            // Display video player or loading indicator
            if let activePlayer = player {
                VideoPlayer(player: activePlayer)
                    // Consider adding controls visibility toggle for video?
            } else {
                // Show loading indicator while player is being prepared
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(progressViewScale) // Use constant
            }
        case .audio, .unknown:
            // Display unsupported state for audio/unknown
            VStack(spacing: errorVStackSpacing) { // Use constant
                Image(systemName: "questionmark.diamond.fill")
                    .foregroundColor(.orange)
                    .font(.largeTitle)
                Text("Unsupported Media")
                    .font(.headline)
                    .foregroundColor(.white)
            }
        @unknown default:
            // Handle future media types
            Text("Unhandled media type")
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Image Loading Logic
    private func loadImageOnlyIfNeeded() async {
        // Only proceed if the view state is currently loading
        guard case .loading = viewState, item.asset.mediaType == .image else { return }

        let assetIdentifier = item.asset.localIdentifier

        // Check cache first
        if let cachedImage = viewModel.cachedImage(for: assetIdentifier, isHighRes: true) { // Check high-res cache
            // Update state on main thread
             DispatchQueue.main.async {
                 self.viewState = .image(displayImage: cachedImage)
             }
            return
        }

        // Setup request options for high quality
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none // We want full size
        options.isSynchronous = false // Run asynchronously
        options.version = .current

        // Cancel any previous request for this view instance
        cancelImageRequest()

        // Progress handler (optional but good for large iCloud downloads)
        options.progressHandler = { progress, error, stop, info in
             if let error = error {
                 print("❌ Error loading full-size image: \(error.localizedDescription)")
             } else {
                 // print("📊 Full-size image progress: \(progress)") // Can be noisy
             }
         }

        print("⬆️ Requesting full-size image data for \(assetIdentifier)")
        // Request image data
        currentRequestID = PHImageManager.default().requestImageDataAndOrientation(
            for: item.asset,
            options: options
        ) { data, _, _, info in
            // Check if request was cancelled
            let isCancelled = info?[PHImageCancelledKey] as? Bool ?? false
            // Check if we got degraded image first (optional)
            _ = info?[PHImageResultIsDegradedKey] as? Bool ?? false

            // Clear request ID once completed or cancelled
             DispatchQueue.main.async { // Ensure thread safety for currentRequestID
                 if self.currentRequestID == info?[PHImageResultRequestIDKey] as? PHImageRequestID {
                     self.currentRequestID = nil
                 }
             }

            if isCancelled {
                print("🚫 Image request cancelled for \(assetIdentifier)")
                return
            }

            // Handle potential error
            if let error = info?[PHImageErrorKey] as? Error {
                print("❌ Error loading full-size image: \(error.localizedDescription)")
                // Don't automatically retry here, let user trigger via UI if needed
                DispatchQueue.main.async {
                    self.viewState = .error(error.localizedDescription)
                }
                return
            }

            // Process data if available
            guard let data = data, let image = UIImage(data: data) else {
                print("⚠️ Full-size image data invalid for asset \(assetIdentifier)")
                 DispatchQueue.main.async {
                     self.viewState = .error("Failed to load image data")
                 }
                return
            }

            // Cache the successfully loaded high-quality image
            // Use isHighRes: true for the detail view cache
            self.viewModel.cacheImage(image, for: assetIdentifier, isHighRes: true)

            // Update view state on main thread
             DispatchQueue.main.async {
                 // Only update if still relevant (e.g., user hasn't swiped away quickly)
                 if self.item.asset.localIdentifier == assetIdentifier {
                      self.viewState = .image(displayImage: image)
                 }
             }
        }
    }

    // Simplified retry - maybe remove if error state provides enough info
    // Or enhance error state with a retry button that calls loadImageOnlyIfNeeded again
    // private func retryFullSizeImageRequest(...) { ... } // Removed for now

    private func cancelImageRequest() {
         if let requestID = currentRequestID {
             print("🚫 Cancelling previous image request \(requestID)")
             PHImageManager.default().cancelImageRequest(requestID)
             currentRequestID = nil
         }
    }

    // MARK: - Notification Handling
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
          forName: Notification.Name("DismissMapPanel"),
          object: nil,
          queue: .main
        ) { _ in
            withAnimation(.spring(response: panelSpringResponse, dampingFraction: panelSpringDamping)) {
                showInfoPanel = false
            }
        }


         NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
         ) { [weak viewModel] _ in
             DispatchQueue.main.async {
                 viewModel?.clearImageCache()
             }
         }
    }

    private func removeNotificationObservers() {
         // Use the name-based removal for safety
         NotificationCenter.default.removeObserver(self, name: Notification.Name("DismissMapPanel"), object: nil)
         NotificationCenter.default.removeObserver(self, name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }
}


// MARK: - Helper Structs & Extensions (Keep at end of file)

// Corner Radius Extension
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

// Shape for applying corner radius selectively
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity // Default to full rounding (like Capsule)
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// Placeholder for video loading (simple play icon)
struct VideoPlayerPlaceholderView: View {
    let asset: PHAsset // Keep asset if needed for future info display

    // MARK: - Constants
    private let iconSize: CGFloat = 60
    private let iconOpacity: Double = 0.8

    var body: some View {
        ZStack {
            Color.black // Background
            Image(systemName: "play.circle.fill")
                .font(.system(size: iconSize, weight: .regular)) // Use constant
                .foregroundColor(.white.opacity(iconOpacity)) // Use constant
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Removed daySuffix function - now handled by Date extension
