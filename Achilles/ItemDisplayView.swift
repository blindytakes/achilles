import SwiftUI
import Photos
import AVKit
import UIKit // Keep for Share Sheet
import PhotosUI // <-- **ADD THIS IMPORT**

// MARK: - State Enum Definition (Updated)
fileprivate enum DetailViewState {
    case loading
    case error(String)
    case image(displayImage: UIImage)
    case livePhoto(displayLivePhoto: PHLivePhoto) // <-- **ADD THIS CASE**
    case unsupported // For types not handled (video is handled separately via player)
}

// MARK: - ItemDisplayView

struct ItemDisplayView: View {
    // MARK: - Properties
    @ObservedObject var viewModel: PhotoViewModel
    let item: MediaItem
    let player: AVPlayer? // Passed down from MediaDetailView
    @Binding var showInfoPanel: Bool

    // Internal State
    @State private var viewState: DetailViewState = .loading // Initial state
    @State private var controlsHidden: Bool = false
    @State private var zoomScale: CGFloat = 1.0 // Used by ZoomableScrollView for static images ONLY
    @Environment(\.dismiss) private var dismiss

    // (Keep all your existing Constants here - unchanged)
    // MARK: - Constants
    // Layout & Frame
    private let locationButtonBottomPadding: CGFloat = 40
    // ... other constants ...
    private let zoomableImageYOffset: CGFloat = -20
    // ... etc ...
    private let visibleOpacity: Double = 1.0

    // Z-Indexes
    private let contentZIndex: Double = 0
    private let locationButtonZIndex: Double = 1
    private let locationPanelZIndex: Double = 2
    
    private let locationButtonFadeDuration: Double = 0.25 // Make sure this is declared if used
    private let panelSpringResponse: Double = 0.4
    private let panelSpringDamping: Double = 0.75

    private let locationPanelHorizontalMargin: CGFloat = 12
    private let locationPanelHeightFactor: CGFloat = 0.65
    private let locationPanelMaxHeight: CGFloat = 400
    private let locationPanelPositionXFactor: CGFloat = 0.5
    private let locationPanelPositionYFactor: CGFloat = 0.45

    private let mapIconWidth: CGFloat = 32            // Needed by locationButton if defined there
    private let mapIconHeight: CGFloat = 24           // Needed by locationButton if defined there
    private let mapIconCornerRadius: CGFloat = 6        // Needed by locationButton if defined there
    private let mapPinIconSize: CGFloat = 26          // Needed by locationButton if defined there
    private let mapPinIconYOffset: CGFloat = -2         // Needed by locationButton if defined there
    private let mapLabelFontSize: CGFloat = 12         // Needed by locationButton if defined there
    private let mapLabelVStackSpacing: CGFloat = 4      // Needed by locationButton if defined there
    private let locationButtonSize: CGFloat = 60        // Needed by locationButton if defined there
    private let locationButtonCornerRadius: CGFloat = 12 // Needed by locationButton if defined there
    private let locationButtonStrokeWidth: CGFloat = 1  // Needed by locationButton if defined there
    private let errorVStackSpacing: CGFloat = 8         // Needed by errorView/unsupportedView
    private let progressViewScale: CGFloat = 1.5       // Needed by loading views

    private let locationButtonBackgroundOpacity: Double = 0.85 // Needed by locationButton
        private let locationButtonShadowOpacity: Double = 0.25   // Needed by locationButton
        private let locationButtonShadowRadius: CGFloat = 4      // Needed by locationButton
        private let locationButtonShadowYOffset: CGFloat = 2     // Needed by locationButton
        private let locationButtonStrokeOpacity: Double = 0.3    // Needed by locationButton
        private let mapIconFillOpacity: Double = 0.2             // Needed by locationButton
        private let mapPinShadowOpacity: Double = 0.25           // Needed by locationButton
        private let mapPinShadowRadius: CGFloat = 1              // Needed by locationButton
        private let mapPinShadowYOffset: CGFloat = 1             // Needed by locationButton
        private let hiddenOpacity: Double = 0.0
    // MARK: - Body
    var body: some View {
        GeometryReader { geometry in
            
            let _ = print(">>> ItemDisplayView [ID: \(item.id)] - Has Location: \(item.asset.location != nil), showInfoPanel: \(showInfoPanel)")

            ZStack(alignment: .bottom) {
                // Main content area (Image, LivePhoto, Video, Loading, Error)
                mainContentSwitchView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle()) // Ensure tappable area
                    .zIndex(contentZIndex) // Base layer

                // Location button overlay (only if location exists and panel is hidden)
                if item.asset.location != nil && !showInfoPanel {
                    locationButton
                        .opacity(controlsHidden ? 0.0 : 1.0) // Use constants if preferred
                        .animation(.easeInOut(duration: 0.25), value: controlsHidden)
                        .zIndex(locationButtonZIndex) // Above content
                }
                
                // Location info panel overlay (only if location exists and panel is shown)
                if showInfoPanel, item.asset.location != nil {
                    let _ = print(">>> ItemDisplayView [ID: \(item.id)] - Rendering Location Panel")
                    LocationInfoPanelView(asset: item.asset)
                         // (Keep existing frame/position/transition/zIndex modifiers)
                        .frame(width: geometry.size.width - locationPanelHorizontalMargin * 2)
                        .frame(maxHeight: min(geometry.size.height * locationPanelHeightFactor, locationPanelMaxHeight))
                        .position(x: geometry.size.width * locationPanelPositionXFactor, y: geometry.size.height * locationPanelPositionYFactor)
                        .transition(.opacity.combined(with: .offset(y: geometry.size.height * 0.1)))
                        .zIndex(locationPanelZIndex)
                }
            }
            .background(Color.black) // Ensure background for entire ZStack
            .id(item.id) // Force redraw when item changes
            .ignoresSafeArea(.all, edges: .all) // Extend to screen edges
        }
        // ** MODIFIED: Use .task(id:) to handle loading for different item types **
        .task(id: item.id) {
             await loadMediaData() // Call the unified loading function
        }
        // ** MODIFIED: Update onChange to handle reset correctly **
        .onChange(of: item.id) { _, _ in // Use correct onChange signature if needed
            // Reset shared UI state when item changes
            showInfoPanel = false
            controlsHidden = false
            zoomScale = 1.0 // Reset zoom scale (only applies to static images)
            // The .task(id:) modifier will handle resetting viewState and loading new data
        }
        .onAppear {
            setupNotificationObservers()
        }
        .onDisappear {
            removeNotificationObservers()
        }
    }

    // MARK: - Location Button View
    private var locationButton: some View {
        Button {
            // Action: Show panel with spring animation
            withAnimation(.spring(response: panelSpringResponse, dampingFraction: panelSpringDamping)) {
                showInfoPanel = true
            }
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

        } label: {
            ZStack {
                // Background with material effect and shadow/stroke
                RoundedRectangle(cornerRadius: locationButtonCornerRadius)
                    .fill(Color(.systemBackground).opacity(locationButtonBackgroundOpacity))
                    .shadow(color: .black.opacity(locationButtonShadowOpacity), radius: locationButtonShadowRadius, x: 0, y: locationButtonShadowYOffset)
                    .overlay(
                        RoundedRectangle(cornerRadius: locationButtonCornerRadius)
                            .stroke(Color.white.opacity(locationButtonStrokeOpacity), lineWidth: locationButtonStrokeWidth)
                    )

                // Content: Icon and Text
                VStack(spacing: mapLabelVStackSpacing) {
                    ZStack {
                         // Pin icon overlay
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: mapPinIconSize, weight: .semibold))
                            .foregroundColor(.red)
                            .shadow(color: .black.opacity(mapPinShadowOpacity), radius: mapPinShadowRadius, x: 0, y: mapPinShadowYOffset)
                    }
                    .frame(height: mapIconHeight) // Give icon area height

                    Text("Map")
                        .font(.system(size: mapLabelFontSize, weight: .medium))
                        .foregroundColor(.primary)
                }
            }
            .frame(width: locationButtonSize, height: locationButtonSize) // Set overall size for the ZStack label
        }
        .padding(.bottom, locationButtonBottomPadding) // Apply padding outside the Button
    }
    // Inside ItemDisplayView.swift

    @ViewBuilder private var mainContentSwitchView: some View {
        // Use GeometryReader if needed for frame calculations below
        GeometryReader { geometry in // Added for potential frame needs
            // Determine content based on the asset's media type first
            switch item.asset.mediaType {
                
            case .image:
                // Branch within .image for static vs live
                if item.asset.mediaSubtypes.contains(.photoLive) {
                    // --- Live Photo Display ---
                    switch viewState {
                    case .loading:
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(1.5)
                    case .error(let message):
                        errorView(message: message)
                    case .livePhoto(let displayLivePhoto):
                        // *** Wrap PHLivePhotoViewRepresentable in ZoomableScrollView ***
                        // Prepare for gesture conflict debugging in ZoomableScrollView!
                        ZoomableScrollView(
                            contentType: .livePhoto,
                            showInfoPanel: $showInfoPanel,
                            controlsHidden: $controlsHidden,
                            zoomScale: $zoomScale,
                            dismissAction: { dismiss() }
                            // Pass a hint about content type IF you modify ZoomableScrollView
                            // contentType: .livePhoto // Example hypothetical modifier
                        ) {
                            PHLivePhotoViewRepresentable(livePhoto: displayLivePhoto)
                            // Ensure the representable fills the space or has a defined size
                            // Depending on PHLivePhotoViewRepresentable's internal sizing,
                            // you might or might not need an explicit .frame modifier here.
                            // Start without it, add if needed.
                        }
                    case .image, .unsupported: // Invalid states
                        errorView(message: "Internal state error (LP expects .livePhoto).")
                    }
                } else {
                    // --- Static Image Display ---
                    switch viewState {
                    case .loading:
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(1.5)
                    case .error(let message):
                        errorView(message: message)
                    case .image(let displayImage):
                        // *** Use ZoomableScrollView for static Image *** (As before)
                        ZoomableScrollView(
                            contentType: .image,
                            showInfoPanel: $showInfoPanel,
                            controlsHidden: $controlsHidden,
                            zoomScale: $zoomScale,
                            dismissAction: { dismiss() }
                            // contentType: .image // Example hypothetical modifier
                        ) {
                            Image(uiImage: displayImage)
                                .resizable()
                                .interpolation(.high)
                                .antialiased(true)
                                .aspectRatio(contentMode: .fit)
                            // Make sure the Image itself can fill the ZoomableScrollView area
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.black)
                            //.offset(y: zoomableImageYOffset) // Offset might be undesirable now
                        }
                    case .livePhoto, .unsupported: // Invalid states
                        errorView(message: "Internal state error (IMG expects .image).")
                    }
                }
                
            case .video:
                // --- Video Display (Standard Player - No Zoom) ---
                if let activePlayer = player {
                    VideoPlayer(player: activePlayer)
                        .onTapGesture { handleTap() } // Use standard tap for controls/play/pause
                } else {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(1.5)
                }
                
            case .audio:
                // Explicitly handle audio (e.g., show unsupported view)
                unsupportedView(message: "Audio files not supported")
                
            case .unknown:
                // Explicitly handle unknown (e.g., show unsupported view)
                unsupportedView(message: "Unknown media type")
                
            @unknown default:
                let _ = print("⚠️ Encountered unhandled PHAssetMediaType: \(item.asset.mediaType.rawValue)")
                unsupportedView(message: "Unsupported media type: \(item.asset.mediaType.rawValue)")
                unsupportedView(message: "Unsupported media type")
            }
        }
    }
            // MARK: - Data Loading (Updated)
            @MainActor // Ensure state updates are on main thread
            private func loadMediaData() async {
                // Reset state to loading *unless* it's video (player state managed externally)
                if item.asset.mediaType != .video {
                    viewState = .loading
                } else {
                    // For video, just ensure any previous image/live photo state is cleared
                    // The actual loading indicator display is handled by checking `player != nil`
                    // in mainContentSwitchView
                    if case .image = viewState { viewState = .loading }
                    if case .livePhoto = viewState { viewState = .loading }
                    // If it was already .loading or .error for a video, leave it
                    print("Video item detected, player state managed externally.")
                    return // Don't proceed with internal loading for video
                }
                
                
                let assetIdentifier = item.asset.localIdentifier
                print("➡️ ItemDisplayView: Loading data for \(assetIdentifier), type: \(item.asset.mediaType.rawValue)")
                
                // --- Fetch based on type ---
                if item.asset.mediaSubtypes.contains(.photoLive) {
                    print("➡️ ItemDisplayView: Requesting Live Photo for \(assetIdentifier)")
                    viewModel.requestLivePhoto(for: item.asset) { [assetIdentifier] fetchedLivePhoto in
                        // Check if view is still relevant before updating state
                        guard self.item.asset.localIdentifier == assetIdentifier else {
                            print("⬅️ ItemDisplayView: Received Live Photo for \(assetIdentifier), but view is no longer relevant.")
                            return
                        }
                        if let validLivePhoto = fetchedLivePhoto {
                            print("⬅️ ItemDisplayView: Received VALID Live Photo for \(assetIdentifier)")
                            self.viewState = .livePhoto(displayLivePhoto: validLivePhoto)
                        } else {
                            print("⬅️ ItemDisplayView: Received NIL Live Photo for \(assetIdentifier)")
                            self.viewState = .error("Failed to load Live Photo")
                        }
                    }
                } else if item.asset.mediaType == .image {
                    print("➡️ ItemDisplayView: Requesting static image for \(assetIdentifier)")
                    // Fetch static image (using existing logic, adapted)
                    viewModel.requestFullSizeImage(for: item.asset) { [assetIdentifier] image in
                        // Ensure view is still relevant
                        guard self.item.asset.localIdentifier == assetIdentifier else {
                            print("⬅️ ItemDisplayView: Received image for \(assetIdentifier), but view is no longer relevant.")
                            return
                        }
                        if let validImage = image {
                            print("⬅️ ItemDisplayView: Received VALID full-size image for \(assetIdentifier)")
                            self.viewState = .image(displayImage: validImage)
                        } else {
                            print("⬅️ ItemDisplayView: Received NIL full-size image for \(assetIdentifier)")
                            self.viewState = .error("Failed to load image")
                        }
                    }
                } else {
                    // Should not reach here if video check is done earlier, but as fallback:
                    print("➡️ ItemDisplayView: Unsupported type (\(item.asset.mediaType.rawValue)) for internal loading.")
                    viewState = .unsupported
                }
            }
            
            // MARK: - UI Helper Views (NEW/Refactored)
            
            // Helper for displaying errors consistently
            @ViewBuilder private func errorView(message: String) -> some View {
                VStack(spacing: 8) { // Use constant if defined
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.largeTitle)
                    Text("Error Loading Media")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.gray) // Use gray for secondary text
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            
            // Helper for displaying unsupported state consistently
            @ViewBuilder private func unsupportedView(message: String = "Unsupported Media Type") -> some View {
                VStack(spacing: 8) { // Use constant if defined
                    Image(systemName: "questionmark.diamond.fill")
                        .foregroundColor(.orange)
                        .font(.largeTitle)
                    Text(message)
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
            
            // MARK: - Tap Gesture Handling (NEW)
            private func handleTap() {
                // Toggle controls visibility on tap for non-zoomable content
                // ZoomableScrollView handles its own tap internally for controls
                if item.asset.mediaType == .video || item.asset.mediaSubtypes.contains(.photoLive) {
                    controlsHidden.toggle()
                    // Also hide/show info panel if needed based on controls state?
                    // If controls become visible, ensure info panel is hidden maybe?
                    if !controlsHidden && showInfoPanel {
                        withAnimation(.spring(response: panelSpringResponse, dampingFraction: panelSpringDamping)) {
                            showInfoPanel = false
                        }
                    }
                }
            }
            
            
            // (Keep Notification Handling - unchanged)
            private func setupNotificationObservers() {
                NotificationCenter.default.addObserver(
                    forName: Notification.Name("DismissMapPanel"),
                    object: nil,
                    queue: .main
                ) { _ in
                    withAnimation(.spring(response: self.panelSpringResponse,
                                          dampingFraction: self.panelSpringDamping)) {
                        self.showInfoPanel = false
                    }
                }
                
                NotificationCenter.default.addObserver(
                    forName: UIApplication.didReceiveMemoryWarningNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    // This closure will capture `viewModel` strongly,
                    // but that’s fine—PhotoViewModel is a long-lived object anyway.
                    viewModel.clearImageCache()
                }
            }
            
            // Don’t forget to remove them in `removeNotificationObservers()` as you already do.
            
            
            private func removeNotificationObservers() {
                print("Removing notification observers for ItemDisplayView") // Debug print
                // Remove *specific* observers using the name
                // Note: Removing 'self' might not work correctly if weak self was used in closure.
                // It's often safer to store the observer token returned by addObserver and remove using that token.
                // But for simplicity for now, try removing by name:
                NotificationCenter.default.removeObserver(self, name: Notification.Name("DismissMapPanel"), object: nil)
                NotificationCenter.default.removeObserver(self, name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
                
            }
        }
    
