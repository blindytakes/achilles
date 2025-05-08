// MediaDetailView.swift

import SwiftUI
import Photos
import AVKit
import UIKit          // For the share sheet
import PhotosUI      // For PHLivePhotoViewRepresentable

struct MediaDetailView: View {
    // MARK: - Inputs
    @ObservedObject var viewModel: PhotoViewModel
    let itemsForYear: [MediaItem]
    let selectedItemID: String

    // MARK: - State
    @State private var currentItemIndex: Int = 0
    @Environment(\.dismiss) var dismiss

    @State private var itemToShare: ShareableItem? = nil
    @State private var isFetchingShareItem = false
    @State private var showLocationPanel: Bool = false
    @State private var currentPlayer: AVPlayer? = nil
    @State private var currentPlayerItemURL: URL? = nil
    @State private var controlsHidden: Bool = false

    var body: some View {
        NavigationView {
            ZStack {
                TabView(selection: $currentItemIndex) {
                    ForEach(Array(itemsForYear.enumerated()), id: \.element.id) { index, item in
                        ItemDisplayView(
                            viewModel: viewModel,
                            item: item,
                            player: currentPlayer,
                            showInfoPanel: $showLocationPanel,
                            controlsHidden: $controlsHidden,
                            onSingleTap: {
                                withAnimation(.easeInOut) {
                                    controlsHidden.toggle()
                                    showLocationPanel = false
                                }
                            }
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .background(Color.black)
                .ignoresSafeArea(.container, edges: [.top, .bottom])
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(titleForCurrentItem())
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    shareButton()
                }
            }
            .navigationBarHidden(controlsHidden)
            .accentColor(.white)
        }
        .navigationViewStyle(.stack)
        .onAppear {
            currentItemIndex = itemsForYear.firstIndex(where: { $0.id == selectedItemID }) ?? 0
            updatePlayerForCurrentIndex()
        }
        .onChange(of: currentItemIndex) { _, _ in
            updatePlayerForCurrentIndex()
            showLocationPanel = false
        }
        .onDisappear {
            currentPlayer?.pause()
        }
        .sheet(item: $itemToShare) { shareable in
            ActivityViewControllerRepresentable(activityItems: shareable.items)
                .onDisappear { itemToShare = nil }
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
        if item.asset.mediaType == .video {
            let videoId = item.id
            Task {
                let url = await viewModel.requestVideoURL(for: item.asset)
                guard currentItem()?.id == videoId,
                      let validURL = url,
                      validURL != currentPlayerItemURL
                else { return }
                let newPlayer = AVPlayer(url: validURL)
                await MainActor.run {
                    currentPlayer?.pause()
                    currentPlayer = newPlayer
                    currentPlayerItemURL = validURL
                    currentPlayer?.play()
                }
            }
        } else {
            currentPlayer?.pause()
            currentPlayer = nil
            currentPlayerItemURL = nil
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

    @ViewBuilder
    private func shareButton() -> some View {
        Button { prepareAndShareCurrentItem() } label: {
            if isFetchingShareItem {
                ProgressView().tint(.white)
            } else {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        .disabled(currentItem() == nil || isFetchingShareItem)
    }

    private func prepareAndShareCurrentItem() {
        guard let item = currentItem(), !isFetchingShareItem else { return }
        isFetchingShareItem = true
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
            await MainActor.run {
                isFetchingShareItem = false
                if let valid = shareable {
                    itemToShare = ShareableItem(items: [valid])
                }
            }
        }
    }
}



// MARK: - Share Sheet Helpers
struct ShareableItem: Identifiable {
    let id = UUID()
    let items: [Any]
}

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

