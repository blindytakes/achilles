import SwiftUI
import Photos
import AVKit
import UIKit

// MARK: - State Enum Definition
fileprivate enum DetailViewState {
    case loading
    case error(String)
    case image(displayImage: UIImage)
    case unsupported
}

// MARK: - ItemDisplayView

struct ItemDisplayView: View {
    @ObservedObject var viewModel: PhotoViewModel
    let item: MediaItem
    let player: AVPlayer?
    @Binding var showInfoPanel: Bool

    @State private var viewState: DetailViewState = .loading
    @State private var controlsHidden: Bool = false
    @State private var zoomScale: CGFloat = 1.0
    @Environment(\.dismiss) private var dismiss
    @State private var currentRequestID: PHImageRequestID?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                mainContentSwitchView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .zIndex(0)
                
                // Always show location button if location exists and the panel isn't already showing
                if item.asset.location != nil && !showInfoPanel {
                    locationButton
                        .opacity(controlsHidden ? 0 : 1)
                        .animation(.easeInOut(duration: 0.25), value: controlsHidden)
                        .zIndex(1)
                }
                    
                if showInfoPanel && item.asset.location != nil {
                    // Map only - absolutely no container or background
                    LocationInfoPanelView(asset: item.asset)
                        .frame(width: geometry.size.width - 12)
                        .frame(maxHeight: min(geometry.size.height * 0.65, 400))
                        .position(x: geometry.size.width / 2, y: geometry.size.height * 0.45)
                        .transition(.opacity)
                        .zIndex(2)
                }
            }
            .background(Color.black)
            .id(item.id)
            .ignoresSafeArea(.all, edges: .all)
        }
        .task { await loadImageOnlyIfNeeded() }
        .onChange(of: item.id) { _, _ in
            if item.asset.mediaType == .image {
                viewState = .loading
            } else {
                viewState = .unsupported
            }
            
            // Reset panel state when item changes
            showInfoPanel = false
        }
        .onAppear {
            
            // Listen for dismiss button taps
            NotificationCenter.default.addObserver(
                forName: Notification.Name("DismissMapPanel"),
                object: nil,
                queue: .main
            ) { _ in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    showInfoPanel = false
                }
            }
            
            // Add memory warning observer - dispatch to main actor
            NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil,
                queue: .main
            ) { [weak viewModel] _ in
                // Dispatch the call to the main actor
                DispatchQueue.main.async {
                    viewModel?.clearImageCache()
                }
            }
        }
        .onDisappear {
            // Cancel any ongoing image request
            if let requestID = currentRequestID {
                PHImageManager.default().cancelImageRequest(requestID)
                currentRequestID = nil
            }
            
            // Remove memory warning observer
            NotificationCenter.default.removeObserver(self, name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
            
            // Remove MapPanel observers
            NotificationCenter.default.removeObserver(self, name: Notification.Name("DismissMapPanel"), object: nil)
        }
    }
    
    // MARK: - Location Button
    
    private var locationButton: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                showInfoPanel = true
                
                // Provide haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }
        } label: {
            ZStack {
                // Background with map-like design
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground).opacity(0.85))
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                    .frame(width: 60, height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                
                // Map icon and label
                VStack(spacing: 4) {
                    ZStack {
                        // Stylized map icon
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 32, height: 24)
                        
                        // Pin overlay
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(.red)
                            .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
                            .offset(y: -2)
                    }
                    
                    Text("Map")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(.bottom, 40) // Position higher from the bottom
    }

    @ViewBuilder private var mainContentSwitchView: some View {
        switch item.asset.mediaType {
        case .image:
            switch viewState {
            case .loading:
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            case .error(let message):
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.largeTitle)
                    Text("Error Loading Media")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            case .image(let displayImage):
                ZoomableScrollView(
                    showInfoPanel: $showInfoPanel,
                    controlsHidden: $controlsHidden,
                    zoomScale: $zoomScale,
                    dismissAction: { dismiss() }
                ) {
                    Image(uiImage: displayImage)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                        .offset(y: -20)
                }
            case .unsupported:
                Text("Unsupported image state?")
                    .foregroundColor(.secondary)
            }
        case .video:
            if let activePlayer = player {
                VideoPlayer(player: activePlayer)
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            }
        case .audio, .unknown:
            VStack(spacing: 8) {
                Image(systemName: "questionmark.diamond.fill")
                    .foregroundColor(.orange)
                    .font(.largeTitle)
                Text("Unsupported Media")
                    .font(.headline)
                    .foregroundColor(.white)
            }
        @unknown default:
            Text("Unhandled media type")
        }
    }

    private func loadImageOnlyIfNeeded() async {
        guard case .loading = viewState else { return }
        
        let assetIdentifier = item.asset.localIdentifier
        
        // Check cache using ViewModel's helper method
        if let cachedImage = viewModel.cachedImage(for: assetIdentifier) {
            DispatchQueue.main.async {
                self.viewState = .image(displayImage: cachedImage)
            }
            return
        }
        
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.isSynchronous = false
        options.version = .current
        options.progressHandler = { progress, error, stop, info in
            if let error = error {
                print("❌ Error loading full-size image: \(error.localizedDescription)")
                print("📊 Progress: \(progress)")
                if progress < 1.0 {
                    self.retryFullSizeImageRequest(targetSize: PHImageManagerMaximumSize, assetIdentifier: assetIdentifier)
                }
            }
        }
        
        // Request the highest quality version of the image
        currentRequestID = PHImageManager.default().requestImageDataAndOrientation(
            for: item.asset,
            options: options
        ) { data, _, _, info in
            self.currentRequestID = nil
            
            if let error = info?[PHImageErrorKey] as? Error {
                print("❌ Error loading full-size image: \(error.localizedDescription)")
                self.retryFullSizeImageRequest(targetSize: PHImageManagerMaximumSize, assetIdentifier: assetIdentifier)
                return
            }
            
            guard let data = data,
                  let image = UIImage(data: data) else {
                print("⚠️ Full-size image was nil for asset \(assetIdentifier)")
                DispatchQueue.main.async {
                    self.viewState = .error("Failed to load image")
                }
                return
            }
            
            // Cache the high-quality image
            self.viewModel.cacheImage(image, for: assetIdentifier)
            
            DispatchQueue.main.async {
                self.viewState = .image(displayImage: image)
            }
        }
    }
    
    private func retryFullSizeImageRequest(targetSize: CGSize, assetIdentifier: String) {
        let retryOptions = PHImageRequestOptions()
        retryOptions.isNetworkAccessAllowed = true
        retryOptions.deliveryMode = .highQualityFormat
        retryOptions.resizeMode = .none
        retryOptions.isSynchronous = false
        retryOptions.version = .current
        
        // Cancel existing request before retrying
        if let existingRequestID = currentRequestID {
            PHImageManager.default().cancelImageRequest(existingRequestID)
        }
        
        currentRequestID = PHImageManager.default().requestImageDataAndOrientation(
            for: item.asset,
            options: retryOptions
        ) { data, _, _, retryInfo in
            self.currentRequestID = nil
            
            if let data = data,
               let retryImage = UIImage(data: data) {
                self.viewModel.cacheImage(retryImage, for: assetIdentifier)
                DispatchQueue.main.async {
                    self.viewState = .image(displayImage: retryImage)
                }
            } else {
                print("⚠️ Retry failed for asset \(assetIdentifier)")
                DispatchQueue.main.async {
                    self.viewState = .error("Failed to load image after retry")
                }
            }
        }
    }
}

// MARK: - Corner Radius Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
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

struct VideoPlayerPlaceholderView: View {
    let asset: PHAsset
    var body: some View {
        ZStack {
            Color.black
            Image(systemName: "play.circle.fill")
                .font(.system(size: 60, weight: .regular))
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}



