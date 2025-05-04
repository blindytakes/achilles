import SwiftUI
import Photos
import AVKit
import UIKit            // For Share Sheet
import PhotosUI        // For PHLivePhotoViewRepresentable

// MARK: - State Enum
fileprivate enum DetailViewState {
    case loading
    case error(String)
    case image(displayImage: UIImage)
    case livePhoto(displayLivePhoto: PHLivePhoto)
    case unsupported
}

struct ItemDisplayView: View {
    // MARK: - Inputs
    @ObservedObject var viewModel: PhotoViewModel
    let item: MediaItem
    let player: AVPlayer?
    @Binding var showInfoPanel: Bool
    @Binding var controlsHidden: Bool
    let onSingleTap: () -> Void

    // MARK: - Internal State
    @State private var viewState: DetailViewState = .loading
    @State private var zoomScale: CGFloat = 1.0
    @Environment(\.dismiss) private var dismiss

    // MARK: - Constants
    private let locationButtonBottomPadding: CGFloat = 40
    private let contentZIndex: Double = 0
    private let locationButtonZIndex: Double = 1
    private let locationPanelZIndex: Double = 2

    private let panelSpringResponse: Double = 0.4
    private let panelSpringDamping: Double = 0.75

    private let locationPanelHorizontalMargin: CGFloat = 12
    private let locationPanelHeightFactor: Double = 0.65
    private let locationPanelMaxHeight: CGFloat = 400
    private let locationPanelPositionXFactor: CGFloat = 0.5
    private let locationPanelPositionYFactor: CGFloat = 0.45

    private let mapIconHeight: CGFloat = 24
    private let mapPinIconSize: CGFloat = 26
    private let mapPinShadowOpacity: Double = 0.25
    private let mapPinShadowRadius: CGFloat = 1
    private let mapPinShadowYOffset: CGFloat = 1

    private let mapLabelFontSize: CGFloat = 12
    private let mapLabelVStackSpacing: CGFloat = 4
    private let locationButtonSize: CGFloat = 60
    private let locationButtonCornerRadius: CGFloat = 12
    private let locationButtonBackgroundOpacity: Double = 0.85
    private let locationButtonShadowOpacity: Double = 0.25
    private let locationButtonShadowRadius: CGFloat = 4
    private let locationButtonShadowYOffset: CGFloat = 2
    private let locationButtonStrokeOpacity: Double = 0.3
    private let locationButtonStrokeWidth: CGFloat = 1

    // MARK: - Body
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                mainContentSwitchView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .zIndex(contentZIndex)

                // Map button overlay
                if item.asset.location != nil && !showInfoPanel && !controlsHidden {
                    locationButton
                        .transition(.opacity)
                        .zIndex(locationButtonZIndex)
                }

                // Location info panel
                if showInfoPanel, item.asset.location != nil {
                    LocationInfoPanelView(asset: item.asset)
                        .frame(width: geometry.size.width - locationPanelHorizontalMargin * 2)
                        .frame(maxHeight: min(geometry.size.height * locationPanelHeightFactor,
                                              locationPanelMaxHeight))
                        .position(
                            x: geometry.size.width * locationPanelPositionXFactor,
                            y: geometry.size.height * locationPanelPositionYFactor
                        )
                        .transition(.opacity.combined(with: .offset(y: geometry.size.height * 0.1)))
                        .zIndex(locationPanelZIndex)
                }
            }
            .background(Color.black)
            .id(item.id)
            .ignoresSafeArea(.all)
            .simultaneousGesture(
                TapGesture(count: 1)
                    .onEnded {
                        let isZoomed = zoomScale > 1.0
                        if item.asset.mediaType == .video || !isZoomed {
                            onSingleTap()
                        }
                    }
            )
        }
        .task(id: item.id) {
            await loadMediaData()
        }
        .onChange(of: item.id) { _, _ in
            showInfoPanel = false
            controlsHidden = false
            zoomScale = 1.0
        }
        .onAppear {
            setupNotificationObservers()
        }
        .onDisappear {
            removeNotificationObservers()
        }
    }

    // MARK: - Location Button
    private var locationButton: some View {
        Button {
            withAnimation(.spring(response: panelSpringResponse,
                                  dampingFraction: panelSpringDamping)) {
                showInfoPanel = true
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: locationButtonCornerRadius)
                    .fill(Color(.systemBackground).opacity(locationButtonBackgroundOpacity))
                    .shadow(color: .black.opacity(locationButtonShadowOpacity),
                            radius: locationButtonShadowRadius,
                            x: 0, y: locationButtonShadowYOffset)
                    .overlay(
                        RoundedRectangle(cornerRadius: locationButtonCornerRadius)
                            .stroke(Color.white.opacity(locationButtonStrokeOpacity),
                                    lineWidth: locationButtonStrokeWidth)
                    )

                VStack(spacing: mapLabelVStackSpacing) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: mapPinIconSize, weight: .semibold))
                        .foregroundColor(.red)
                        .shadow(color: .black.opacity(mapPinShadowOpacity),
                                radius: mapPinShadowRadius,
                                x: 0, y: mapPinShadowYOffset)
                        .frame(height: mapIconHeight)

                    Text("Map")
                        .font(.system(size: mapLabelFontSize, weight: .medium))
                        .foregroundColor(.primary)
                }
            }
            .frame(width: locationButtonSize, height: locationButtonSize)
        }
        .padding(.bottom, locationButtonBottomPadding)
    }

    // MARK: - Main Content Switcher
    private func mainContentSwitchView() -> AnyView {
        switch item.asset.mediaType {
        case .image where item.asset.mediaSubtypes.contains(.photoLive):
            return livePhotoView()
        case .image:
            return staticImageView()
        case .video:
            if let activePlayer = player {
                return AnyView(
                    VideoPlayer(player: activePlayer)
                )
            } else {
                return AnyView(
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                )
            }
        default:
            return AnyView(
                unsupportedView(message: "Unsupported Media Type")
            )
        }
    }

    private func livePhotoView() -> AnyView {
        switch viewState {
        case .loading:
            return AnyView(
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.5)
            )
        case .livePhoto(let livePhoto):
            return AnyView(
                ZoomableScrollView(
                    contentType: .livePhoto,
                    showInfoPanel: $showInfoPanel,
                    controlsHidden: $controlsHidden,
                    zoomScale: $zoomScale,
                    dismissAction: { dismiss() }
                ) {
                    PHLivePhotoViewRepresentable(livePhoto: livePhoto)
                }
            )
        case .error(let msg):
            return AnyView(errorView(message: msg))
        default:
            return AnyView(errorView(message: "Internal state error"))
        }
    }

    private func staticImageView() -> AnyView {
        switch viewState {
        case .loading:
            return AnyView(
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.5)
            )
        case .image(let uiImage):
            return AnyView(
                ZoomableScrollView(
                    contentType: .image,
                    showInfoPanel: $showInfoPanel,
                    controlsHidden: $controlsHidden,
                    zoomScale: $zoomScale,
                    dismissAction: { dismiss() }
                ) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                }
            )
        case .error(let msg):
            return AnyView(errorView(message: msg))
        default:
            return AnyView(errorView(message: "Internal state error"))
        }
    }

    // MARK: - Data Loading
    @MainActor
    private func loadMediaData() async {
        if item.asset.mediaType != .video {
            viewState = .loading
        } else {
            return
        }

        let id = item.asset.localIdentifier
        if item.asset.mediaSubtypes.contains(.photoLive) {
            viewModel.requestLivePhoto(for: item.asset) { fetched in
                guard self.item.asset.localIdentifier == id else { return }
                viewState = fetched.map { .livePhoto(displayLivePhoto: $0) }
                               ?? .error("Failed to load Live Photo")
            }
        } else if item.asset.mediaType == .image {
            viewModel.requestFullSizeImage(for: item.asset) { img in
                guard self.item.asset.localIdentifier == id else { return }
                viewState = img.map { .image(displayImage: $0) }
                             ?? .error("Failed to load image")
            }
        } else {
            viewState = .unsupported
        }
    }

    // MARK: - Helper Views
    @ViewBuilder private func errorView(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle).foregroundColor(.orange)
            Text("Error Loading Media").font(.headline).foregroundColor(.white)
            Text(message)
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    @ViewBuilder private func unsupportedView(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.diamond.fill")
                .font(.largeTitle).foregroundColor(.orange)
            Text(message).font(.headline).foregroundColor(.white)
        }
    }

    // MARK: - Notification Observers
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("DismissMapPanel"),
            object: nil,
            queue: .main
        ) { _ in
            withAnimation(.spring(response: panelSpringResponse,
                                  dampingFraction: panelSpringDamping)) {
                showInfoPanel = false
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak viewModel] _ in
            Task { @MainActor in
                viewModel?.clearImageCache()
            }
        }
    }

    private func removeNotificationObservers() {
        NotificationCenter.default.removeObserver(self,
                                                  name: Notification.Name("DismissMapPanel"),
                                                  object: nil)
        NotificationCenter.default.removeObserver(self,
                                                  name: UIApplication.didReceiveMemoryWarningNotification,
                                                  object: nil)
    }
}

