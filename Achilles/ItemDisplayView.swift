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
                    
                if showInfoPanel && item.asset.location != nil {
                    VStack(spacing: 0) {
                        // Drag handle
                        Rectangle()
                            .fill(Color.white.opacity(0.5))
                            .frame(width: 40, height: 4)
                            .cornerRadius(2)
                            .padding(.top, 15)
                            .padding(.bottom, 10)
                        
                        LocationInfoPanelView(asset: item.asset)
                            .padding(.bottom, 20)
                    }
                    .frame(width: geometry.size.width - 20)
                    .frame(height: min(geometry.size.height * 0.6, 500))
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: -5)
                    )
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2 + dragOffset)
                    .transition(
                        .asymmetric(
                            insertion: .opacity,
                            removal: .opacity
                        )
                    )
                    .zIndex(2) // Higher z-index than the indicator
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                // Allow dragging in any direction but limit to reasonable amounts
                                dragOffset = min(100, max(-100, -value.translation.height))
                            }
                            .onEnded { value in
                                let velocity = -value.predictedEndTranslation.height / max(1, abs(value.translation.height))
                                
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                                    // If swipe down is significant, hide panel
                                    if dragOffset < -30 || velocity < -0.5 {
                                        showInfoPanel = false
                                    }
                                    
                                    // Reset drag offset
                                    dragOffset = 0
                                }
                            }
                    )
                    // Also add a tap gesture to dismiss
                    .onTapGesture {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                            showInfoPanel = false
                        }
                    }
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



