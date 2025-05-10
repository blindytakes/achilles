// Achilles/Views/Media/ItemDisplayView.swift

import SwiftUI
import Photos
import AVKit
import UIKit // For Share Sheet
import PhotosUI // For PHLivePhotoViewRepresentable

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
    let player: AVPlayer? // For video
    @Binding var showInfoPanel: Bool
    @Binding var controlsHidden: Bool
    let onSingleTap: () -> Void

    // MARK: - Internal State
    @State private var viewState: DetailViewState = .loading
    @State private var currentZoomScale: CGFloat = 1.0 // Local state for zoom, bound to ZoomableScrollView

    @Environment(\.dismiss) private var dismiss

    // MARK: - Constants
    private struct ViewConstants {
        static let zoomSlightlyAboveMinimum: CGFloat = 1.01
        static let panelSpringResponse: Double = 0.4
        static let panelSpringDamping: Double = 0.75
    }

    // MARK: - Body
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .center) {
                mainContentSwitchView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .zIndex(0)

                if item.asset.location != nil && !showInfoPanel && !controlsHidden {
                    locationButton
                        .transition(.opacity.animation(.easeInOut))
                        .position(x: geometry.size.width / 2,
                                  y: geometry.size.height - (geometry.safeAreaInsets.bottom - 50 ))
                        .zIndex(1)
                }
                if showInfoPanel, let location = item.asset.location {
                    LocationInfoPanelView(
                      asset: item.asset,
                      viewModel: viewModel,
                      onDismiss: {
                        withAnimation(.spring(response: ViewConstants.panelSpringResponse, dampingFraction: ViewConstants.panelSpringDamping)) {
                          showInfoPanel = false
                        }
                      }
                    )
                    .transition(.opacity.combined(with: .offset(y: geometry.size.height * 0.1)))
                    .zIndex(2)
                }
            }
            .background(Color.black)
            .id(item.id)
            .ignoresSafeArea(.all)
            .simultaneousGesture(
                TapGesture(count: 1)
                    .onEnded {
                        if currentZoomScale <= (ViewConstants.zoomSlightlyAboveMinimum + 0.01) && !showInfoPanel {
                            onSingleTap()
                        } else if showInfoPanel {
                             withAnimation { showInfoPanel = false }
                        }
                    }
            )
        }
        .task(id: item.id) {
            await loadMediaData()
        }
        .onChange(of: item.id) { _, newId in
            print("ItemDisplayView: item.id changed to \(newId). Resetting local state.")
            showInfoPanel = false
            currentZoomScale = 1.0
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
            withAnimation(.spring(response: ViewConstants.panelSpringResponse, dampingFraction: ViewConstants.panelSpringDamping)) {
                showInfoPanel = true
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground).opacity(0.85))
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                VStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.red)
                        .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
                        .frame(height: 24)
                    Text("Map")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                }
            }
            .frame(width: 60, height: 60)
        }
    }

    // MARK: - Main Content Switcher
    @ViewBuilder
    private func mainContentSwitchView() -> some View {
        switch item.asset.mediaType {
        case .image where item.asset.mediaSubtypes.contains(.photoLive):
            livePhotoView()
        case .image:
            staticImageView()
        case .video:
            if let activePlayer = player { VideoPlayer(player: activePlayer).ignoresSafeArea() }
            else { ProgressView().progressViewStyle(.circular).scaleEffect(1.5) }
        default:
            unsupportedView(message: "Unsupported Media Type")
        }
    }

    // MARK: - Live‑Photo Content
    @ViewBuilder
    private func livePhotoView() -> some View {
        switch viewState {
        case .loading: ProgressView().progressViewStyle(.circular).scaleEffect(1.5)
        case .livePhoto(let livePhoto):
            ZoomableScrollView(
                contentId: item.id,
                contentType: .livePhoto,
                showInfoPanel: $showInfoPanel,
                controlsHidden: $controlsHidden,
                zoomScale: $currentZoomScale,
                dismissAction: { dismiss() }
            ) {
                PHLivePhotoViewRepresentable(livePhoto: livePhoto)
            }
        case .error(let msg): errorView(message: msg)
        default: errorView(message: "Internal state error (LivePhoto)")
        }
    }

    // MARK: - Static‑Image Content
    @ViewBuilder
    private func staticImageView() -> some View {
        switch viewState {
        case .loading: ProgressView().progressViewStyle(.circular).scaleEffect(1.5)
        case .image(let uiImage):
            ZoomableScrollView(
                contentId: item.id,
                contentType: .image,
                showInfoPanel: $showInfoPanel,
                controlsHidden: $controlsHidden,
                zoomScale: $currentZoomScale,
                dismissAction: { dismiss() }
            ) {
                Image(uiImage: uiImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
        case .error(let msg): errorView(message: msg)
        default: errorView(message: "Internal state error (Image)")
        }
    }

    // MARK: - Data Loading
    @MainActor
    private func loadMediaData() async {
        let currentItemID = item.asset.localIdentifier
        
        if item.asset.mediaType != .video {
            if case .loading = viewState { /* Potentially check if it's for currentItemID */ }
            else { viewState = .loading }
        } else { return }

        if item.asset.mediaSubtypes.contains(.photoLive) {
            viewModel.requestLivePhoto(for: item.asset) { fetchedLivePhoto in // Removed [weak self]
                // `self` is implicitly captured. Check against currentItemID.
                guard self.item.asset.localIdentifier == currentItemID else {
                    return
                }
                self.viewState = fetchedLivePhoto.map { .livePhoto(displayLivePhoto: $0) }
                               ?? .error("Failed to load Live Photo")
            }
        } else if item.asset.mediaType == .image {
            viewModel.requestFullSizeImage(for: item.asset) { fetchedImage in // Removed [weak self]
                // `self` is implicitly captured. Check against currentItemID.
                guard self.item.asset.localIdentifier == currentItemID else {
                    return
                }
                self.viewState = fetchedImage.map { .image(displayImage: $0) }
                             ?? .error("Failed to load image")
            }
        } else if item.asset.mediaType != .video {
            viewState = .unsupported
        }
    }

    // MARK: - Helper Views
    @ViewBuilder private func errorView(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundColor(.orange)
            Text("Error Loading Media").font(.headline).foregroundColor(.white)
            Text(message).font(.caption).foregroundColor(.gray).multilineTextAlignment(.center).padding(.horizontal)
        }
    }

    @ViewBuilder private func unsupportedView(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.diamond.fill").font(.largeTitle).foregroundColor(.orange)
            Text(message).font(.headline).foregroundColor(.white)
        }
    }

    // MARK: - Notification Observers
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("DismissMapPanel"), object: nil, queue: .main
        ) { _ in
            withAnimation(.spring(response: ViewConstants.panelSpringResponse, dampingFraction: ViewConstants.panelSpringDamping)) {
                self.showInfoPanel = false // Explicit self for clarity in closure
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak viewModel] _ in // [weak viewModel] is fine as viewModel is a class (ObservableObject)
            Task { @MainActor in
                viewModel?.clearImageCache()
            }
        }
    }

    private func removeNotificationObservers() {
        NotificationCenter.default.removeObserver(self, name: Notification.Name("DismissMapPanel"), object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }
}

// MARK: - Live Photo View Representable
struct PHLivePhotoViewRepresentable: UIViewRepresentable {
    var livePhoto: PHLivePhoto?
    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        return view
    }
    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        uiView.livePhoto = livePhoto
    }
}
