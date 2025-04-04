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

    var body: some View {
        ZStack(alignment: .bottom) {
            mainContentSwitchView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .zIndex(0)

            if showInfoPanel {
                LocationInfoPanelView(asset: item.asset)
                    .background(.ultraThinMaterial)
                    .cornerRadius(15, corners: [.topLeft, .topRight])
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
                    .onTapGesture {
                        withAnimation { showInfoPanel = false }
                    }
            }
        }
        .background(Color.black)
        .task { await loadImageOnlyIfNeeded() }
        .id(item.id)
        .ignoresSafeArea(.all, edges: .all)
        .onChange(of: item.id) { _, _ in
            if item.asset.mediaType == .image {
                viewState = .loading
            } else {
                viewState = .unsupported
            }
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

