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
    @State private var dragOffset: CGFloat = 0
    @Environment(\.dismiss) private var dismiss

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
                        .position(x: geometry.size.width / 2, y: geometry.size.height * 0.45 + dragOffset)
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
            dragOffset = 0
        }
        .onAppear {
            // Listen for map panel drag notifications
            NotificationCenter.default.addObserver(
                forName: Notification.Name("MapPanelDragChanged"),
                object: nil,
                queue: .main
            ) { notification in
                if let userInfo = notification.userInfo,
                   let translation = userInfo["translation"] as? CGSize {
                    // Only allow downward dragging (ignore upward)
                    let dragAmount = -translation.height
                    if dragAmount <= 0 {
                        dragOffset = max(-150, dragAmount * 0.8)
                    }
                }
            }
            
            NotificationCenter.default.addObserver(
                forName: Notification.Name("MapPanelDragEnded"),
                object: nil,
                queue: .main
            ) { notification in
                if let userInfo = notification.userInfo,
                   let predictedEndTranslation = userInfo["predictedEndTranslation"] as? CGSize {
                    let velocity = -predictedEndTranslation.height / max(1, abs(predictedEndTranslation.height))
                    
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        // If significant downward swipe or velocity, hide panel
                        if dragOffset < -20 || velocity < -0.3 {
                            showInfoPanel = false
                        }
                        
                        // Reset drag offset
                        dragOffset = 0
                    }
                }
            }
            
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
        }
        .onDisappear {
            // Remove observers when view disappears
            NotificationCenter.default.removeObserver(self, name: Notification.Name("MapPanelDragChanged"), object: nil)
            NotificationCenter.default.removeObserver(self, name: Notification.Name("MapPanelDragEnded"), object: nil)
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

    @MainActor
    func loadImageOnlyIfNeeded() async {
        guard item.asset.mediaType == .image, case .loading = viewState else { return }
        let imageData = await viewModel.requestFullImageData(for: item.asset)
        guard case .loading = viewState else { return }

        if let data = imageData, let uiImage = UIImage(data: data) {
            self.viewState = .image(displayImage: uiImage)
        } else {
            self.viewState = .error("Could not load full image.")
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

// MARK: - Date Suffix Helper
func daySuffix(for date: Date) -> String {
    let calendar = Calendar.current
    let day = calendar.component(.day, from: date)
    switch day {
    case 11, 12, 13: return "th"
    default:
        switch day % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
}




