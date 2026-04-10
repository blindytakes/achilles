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
    let yearsAgo: Int

    // MARK: State
    @State private var currentItemIndex: Int = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var shareState: ShareState = .idle
    @State private var showLocationPanel: Bool = false
    @State private var currentPlayer: AVPlayer? = nil
    @State private var currentPlayerItemURL: URL? = nil
    @State private var controlsHidden: Bool = false
    @State private var prefetchedVideoURLs: [String: URL] = [:] // IMPROVEMENT 3: Cached video URLs for adjacent items

    var body: some View {
        NavigationStack { content }
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
                prefetchAdjacentVideoURLs() // IMPROVEMENT 3
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
            currentPlayer?.replaceCurrentItem(with: nil) // IMPROVEMENT 5: Clear item instead of discarding player
            currentPlayerItemURL = nil
            return
        }

        guard item.asset.mediaType == .video else {
            currentPlayer?.pause()
            currentPlayer?.replaceCurrentItem(with: nil) // IMPROVEMENT 5
            currentPlayerItemURL = nil
            return
        }

        let videoId = item.id
        Task {
            // IMPROVEMENT 3: Check prefetched cache first
            if let cachedURL = prefetchedVideoURLs[item.asset.localIdentifier] {
                guard currentItem()?.id == videoId, cachedURL != currentPlayerItemURL else { return }
                // IMPROVEMENT 5: Reuse player, swap item
                let playerItem = AVPlayerItem(url: cachedURL)
                if currentPlayer == nil {
                    currentPlayer = AVPlayer(playerItem: playerItem)
                } else {
                    currentPlayer?.replaceCurrentItem(with: playerItem)
                }
                currentPlayerItemURL = cachedURL
                currentPlayer?.play()
                return
            }

            let url = await viewModel.requestVideoURL(for: item.asset)
            guard currentItem()?.id == videoId,
                  let validURL = url,
                  validURL != currentPlayerItemURL
            else { return }

            // IMPROVEMENT 5: Reuse player, swap item
            let playerItem = AVPlayerItem(url: validURL)
            if currentPlayer == nil {
                currentPlayer = AVPlayer(playerItem: playerItem)
            } else {
                currentPlayer?.replaceCurrentItem(with: playerItem)
            }
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

    // IMPROVEMENT 3: Prefetch video URLs for items at currentIndex ± 1
    @MainActor
    private func prefetchAdjacentVideoURLs() {
        let indicesToPrefetch = [currentItemIndex - 1, currentItemIndex, currentItemIndex + 1]
            .filter { itemsForYear.indices.contains($0) }

        // Evict stale URLs outside the ±1 window (temporary file paths can expire)
        let activeAssetIds = Set(indicesToPrefetch.map { itemsForYear[$0].asset.localIdentifier })
        prefetchedVideoURLs = prefetchedVideoURLs.filter { activeAssetIds.contains($0.key) }

        for index in indicesToPrefetch {
            let item = itemsForYear[index]
            guard item.asset.mediaType == .video else { continue }
            let assetId = item.asset.localIdentifier
            guard prefetchedVideoURLs[assetId] == nil else { continue }

            Task {
                if let url = await viewModel.requestVideoURL(for: item.asset) {
                    prefetchedVideoURLs[assetId] = url
                    debugLog("Prefetched video URL for adjacent item \(assetId)")
                }
            }
        }
    }

    // MARK: - Share Preparation

    // In Achilles/Views/Media/MediaDetailView.swift

    @MainActor
    private func prepareAndShareCurrentItem() {
        guard let item = currentItem(), case .idle = shareState else { return }
        shareState = .loading

        Task {
            var shareableMedia: Any?
            var constructedShareText: String?

            // Your constraint: all items are at least 1 year old.
            if let creationDate = item.asset.creationDate {
                let formattedDate = creationDate.monthDayOrdinalYearString()
                let yearsAgoText = "\(yearsAgo) year\(yearsAgo == 1 ? "" : "s") ago!"
                constructedShareText = "Check out this ThrowBak from \(formattedDate), \(yearsAgoText)"
            }

            switch item.asset.mediaType { //
            case .image:
                if let data = await viewModel.requestFullImageData(for: item.asset), //
                   let image = UIImage(data: data) {
                    shareableMedia = image
                }
            case .video:
                if let url = currentPlayerItemURL, currentItem()?.id == item.id { //
                    shareableMedia = url
                } else if let url = await viewModel.requestVideoURL(for: item.asset) { //
                    shareableMedia = url
                }
            default:
                break
            }

            if let validMedia = shareableMedia {
                var itemsToShare: [Any] = [validMedia]
                if let shareText = constructedShareText {
                    itemsToShare.append(shareText)
                }
                shareState = .ready(ShareableItem(items: itemsToShare)) //
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

