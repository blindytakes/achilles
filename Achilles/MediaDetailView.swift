//
//  MediaDetailView.swift
//  Achilles
//
//
//  Displays a full‐screen, paged detail view for a single year’s worth of media items.
//  Features:
//    • Conditional use of NavigationStack (iOS 16+) with fallback to NavigationView.
//    • Opens at the tapped photo via selectedItemID → currentItemIndex on appear.
//    • Async video loading & playback driven by `.task(id: currentItem()?.id)`.
//    • Share integration using a unified ShareState enum (idle, loading, ready).
//    • Extracted subviews for clarity: PagedMediaView and MediaShareButton.
//    • Adaptive styling: systemBackground & dynamic accentColor based on colorScheme.
//    • Share‐sheet presentation bound to `shareState == .ready`, resetting on dismiss.
//
//  Responsibilities:
//    1. Manage paging through `itemsForYear`.
//    2. Load and play videos via `viewModel.requestVideoURL`.
//    3. Present share sheet for images and videos.
//    4. Toggle controls and optional location panel on single tap.
//
//  See also:
//    • PagedMediaView.swift
//    • MediaShareButton.swift
//    • ActivityViewControllerRepresentable.swift
//

import SwiftUI
import Photos
import PhotosUI
import AVKit
import UIKit

// MARK: - Share State Management

enum ShareState {
    case idle
    case loading
    case ready(ShareableItem)
}

struct ShareableItem: Identifiable {
    let id = UUID()
    let items: [Any]
}

// MARK: - Main View

struct MediaDetailView: View {
    // MARK: Inputs
    @ObservedObject var viewModel: PhotoViewModel
    let itemsForYear: [MediaItem]
    let selectedItemID: String

    // MARK: State
    @State private var currentItemIndex: Int = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var shareState: ShareState = .idle
    @State private var showLocationPanel: Bool = false
    @State private var currentPlayer: AVPlayer? = nil
    @State private var currentPlayerItemURL: URL? = nil
    @State private var controlsHidden: Bool = false

    var body: some View {
        Group {
            // STEP 1: Conditional NavigationStack on iOS 16+
            if #available(iOS 16, *) {
                NavigationStack { content }
            } else {
                NavigationView { content }
                    .navigationViewStyle(.stack)
            }
        }
        // Adapt accent color based on color scheme
        .accentColor(colorScheme == .dark ? .white : .blue)
    }

    // MARK: Extracted content

    private var content: some View {
        ZStack {
            PagedMediaView(
                items: itemsForYear,
                currentIndex: $currentItemIndex,
                viewModel: viewModel,
                player: currentPlayer,
                showLocationPanel: $showLocationPanel,
                controlsHidden: $controlsHidden
            )
            .background(Color(.systemBackground))
            .ignoresSafeArea(.container, edges: [.top, .bottom])
            // STEP 4: jump to tapped photo on first appear
            .onAppear {
                currentItemIndex = itemsForYear
                    .firstIndex { $0.id == selectedItemID } ?? 0
            }
            // STEP 2: reload when the current item changes
            .task(id: currentItem()?.id) {
                updatePlayerForCurrentIndex()
                showLocationPanel = false
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(titleForCurrentItem())
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                MediaShareButton(
                    shareState: $shareState,
                    onShare: prepareAndShareCurrentItem,
                    hasValidItem: currentItem() != nil
                )
            }
        }
        .navigationBarHidden(controlsHidden)
        .onDisappear {
            currentPlayer?.pause()
        }
        .sheet(
            isPresented: Binding<Bool>(
                get: { if case .ready = shareState { return true }; return false },
                set: { if !$0 { shareState = .idle } }
            ),
            onDismiss: { /* analytics or cleanup */ }
        ) {
            if case .ready(let shareable) = shareState {
                ActivityViewControllerRepresentable(activityItems: shareable.items)
            }
        }
    }

    // MARK: - Player Management

    @MainActor
    private func updatePlayerForCurrentIndex() {
        guard let item = currentItem() else {
            currentPlayer?.pause()
            currentPlayer = nil
            currentPlayerItemURL = nil
            return
        }

        guard item.asset.mediaType == .video else {
            currentPlayer?.pause()
            currentPlayer = nil
            currentPlayerItemURL = nil
            return
        }

        let videoId = item.id
        Task {
            let url = await viewModel.requestVideoURL(for: item.asset)
            guard currentItem()?.id == videoId,
                  let validURL = url,
                  validURL != currentPlayerItemURL
            else { return }

            let newPlayer = AVPlayer(url: validURL)
            currentPlayer?.pause()
            currentPlayer = newPlayer
            currentPlayerItemURL = validURL
            currentPlayer?.play()
        }
    }

    private func currentItem() -> MediaItem? {
        guard itemsForYear.indices.contains(currentItemIndex) else { return nil }
        return itemsForYear[currentItemIndex]
    }

    private func titleForCurrentItem() -> String {
        guard let date = currentItem()?.asset.creationDate else { return "Detail" }
        return date.longDateShortTime()
    }

    // MARK: - Share Preparation

    @MainActor
    private func prepareAndShareCurrentItem() {
        guard let item = currentItem(), case .idle = shareState else { return }
        shareState = .loading

        Task {
            var shareable: Any?
            switch item.asset.mediaType {
            case .image:
                if let data = await viewModel.requestFullImageData(for: item.asset),
                   let image = UIImage(data: data) {
                    shareable = image
                }
            case .video:
                if let url = currentPlayerItemURL, currentItem()?.id == item.id {
                    shareable = url
                } else if let url = await viewModel.requestVideoURL(for: item.asset) {
                    shareable = url
                }
            default:
                break
            }

            if let valid = shareable {
                shareState = .ready(ShareableItem(items: [valid]))
            } else {
                shareState = .idle
            }
        }
    }
}

// MARK: - Extracted Subviews

struct PagedMediaView: View {
    let items: [MediaItem]
    @Binding var currentIndex: Int
    let viewModel: PhotoViewModel
    let player: AVPlayer?
    @Binding var showLocationPanel: Bool
    @Binding var controlsHidden: Bool

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                ItemDisplayView(
                    viewModel: viewModel,
                    item: item,
                    player: player,
                    showInfoPanel: $showLocationPanel,
                    controlsHidden: $controlsHidden
                ) {
                    withAnimation(.easeInOut) {
                        controlsHidden.toggle()
                        showLocationPanel = false
                    }
                }
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }
}

struct MediaShareButton: View {
    @Binding var shareState: ShareState
    let onShare: () -> Void
    let hasValidItem: Bool

    private var canShare: Bool {
        if case .idle = shareState { return hasValidItem }
        return false
    }

    var body: some View {
        Button(action: onShare) {
            if case .loading = shareState {
                ProgressView().tint(.white)
            } else {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        .disabled(!canShare)
    }
}

// MARK: - Share Sheet Helper

struct ActivityViewControllerRepresentable: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

