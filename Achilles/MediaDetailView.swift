import SwiftUI
import Photos
import AVKit
import UIKit // Keep for Share Sheet

struct MediaDetailView: View {
    // --- Inputs ---
    @ObservedObject var viewModel: PhotoViewModel
    let itemsForYear: [MediaItem]
    let selectedItemID: String
    
    // --- State ---
    @State private var currentItemIndex: Int = 0
    @Environment(\.dismiss) var dismiss
    
    // State for Sharing
    @State private var itemToShare: ShareableItem? = nil
    @State private var isFetchingShareItem = false
    
    // State for location panel
    @State private var showLocationPanel: Bool = false
    
    // --- NEW: State for managing ONE active player ---
    @State private var currentPlayer: AVPlayer? = nil
    @State private var currentPlayerItemURL: URL? = nil // Track URL to avoid reloading same video
    
    
    // --- Body ---s
    var body: some View {
        NavigationView {
            TabView(selection: $currentItemIndex) {
                ForEach(Array(itemsForYear.enumerated()), id: \.element.id) { index, item in
                    
                    // --- Pass the shared player down ---
                    // Pass a real binding for showInfoPanel
                    ItemDisplayView(
                        viewModel: viewModel,
                        item: item,
                        player: currentPlayer,
                        showInfoPanel: $showLocationPanel
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black)
            .ignoresSafeArea(.container, edges: [.top, .bottom])
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(titleForCurrentItem())
            .toolbar(content: {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    self.shareButton() 
                }
            })
            
            .accentColor(.white)
        }
        .navigationViewStyle(.stack)
        .onAppear {
            // Set initial index
            currentItemIndex = itemsForYear.firstIndex(where: { $0.id == selectedItemID }) ?? 0
            // Load player for the initial item
            updatePlayerForCurrentIndex()
        }
        // --- Update player when TabView selection changes ---
        .onChange(of: currentItemIndex) { _, _ in // Use correct signature for your target OS
            updatePlayerForCurrentIndex()
        }
        // --- Pause player when the whole sheet dismisses ---
        .onDisappear {
            print("MediaDetailView disappearing, pausing current player.")
            currentPlayer?.pause()
            // Optional: Reset player state if desired when view disappears
            // currentPlayer = nil
            // currentPlayerItemURL = nil
        }
        .sheet(item: $itemToShare) { shareable in
            ActivityViewControllerRepresentable(activityItems: shareable.items)
                .onDisappear { itemToShare = nil }
        }
    }
    
    // MARK: - Player Management
    
    @MainActor // Ensure player updates happen on main thread
    private func updatePlayerForCurrentIndex() {
        print("Updating player for index: \(currentItemIndex)")
        guard let item = currentItem() else {
            print("No current item, pausing and clearing player.")
            currentPlayer?.pause()
            currentPlayer = nil
            currentPlayerItemURL = nil
            return
        }
        
        if item.asset.mediaType == .video {
            // It's a video, load it (asynchronously)
            let videoAsset = item.asset
            let videoId = item.id
            Task {
                print("Requesting URL for video asset: \(videoId)")
                let url = await viewModel.requestVideoURL(for: videoAsset)
                
                // Check if we are still on the same item index after await
                // And if URL is valid and different from the currently loaded one
                guard currentItemIndex == itemsForYear.firstIndex(where: { $0.id == videoId }),
                      let validURL = url,
                      validURL != currentPlayerItemURL else {
                    if url == nil {
                        print("Failed to get URL for video asset: \(videoId)")
                        await MainActor.run { // Ensure state update is on main
                            if currentItem()?.id == videoId { // Check index again
                                currentPlayer?.pause()
                                currentPlayer = nil
                                currentPlayerItemURL = nil
                            }
                        }
                    } else if url == currentPlayerItemURL {
                        print("Video URL is the same, not reloading player. Ensuring playback for \(videoId)")
                        await MainActor.run { currentPlayer?.play() } // Ensure play resumes if needed
                    } else {
                        print("Index changed while loading URL for \(videoId), ignoring.")
                    }
                    return
                }
                
                // URL is new and valid, create/update player
                print("Creating new player for URL: \(validURL)")
                let newPlayer = AVPlayer(url: validURL)
                // Update state
                await MainActor.run {
                    currentPlayer?.pause() // Pause old player
                    currentPlayer = newPlayer
                    currentPlayerItemURL = validURL
                    print("Playing new video: \(videoId)")
                    currentPlayer?.play() // Start playing the new video
                }
            }
        } else {
            // It's an image or other type, ensure no player is active
            print("Current item \(item.id) is not a video, pausing and clearing player.")
            currentPlayer?.pause()
            currentPlayer = nil
            currentPlayerItemURL = nil
        }
    }
    
    
    // MARK: - Helper Functions (Unchanged)
    
    private func currentItem() -> MediaItem? {
        guard currentItemIndex >= 0 && currentItemIndex < itemsForYear.count else { return nil }
        return itemsForYear[currentItemIndex]
    }
    
    private func titleForCurrentItem() -> String {
        guard let item = currentItem(), let date = item.asset.creationDate else { return "Detail" }
        return date.formatLongDateShortTime()
    }
        // MARK: - Toolbar Button Views (Share Button Unchanged)
        
        @ViewBuilder
        private func shareButton() -> some View {
            Button { prepareAndShareCurrentItem() } label: {
                if isFetchingShareItem { ProgressView().tint(.white) }
                else { Label("Share", systemImage: "square.and.arrow.up") }
            }
            .disabled(currentItem() == nil || isFetchingShareItem)
        }
        
        // MARK: - Action Logic (Share Logic Updated to use currentPlayerItemURL)
        
        private func prepareAndShareCurrentItem() {
            guard let item = currentItem(), !isFetchingShareItem else { return }
            isFetchingShareItem = true
            Task {
                var shareable: Any? = nil
                switch item.asset.mediaType {
                case .image:
                    print("Requesting image data for sharing...")
                    if let data = await viewModel.requestFullImageData(for: item.asset), let image = UIImage(data: data) { shareable = image; print("Image data prepared.") }
                    else { print("Failed to get image data for sharing.") }
                case .video:
                    print("Requesting video URL for sharing...")
                    // Use the currently loaded player URL if available and matches current item
                    if let url = currentPlayerItemURL, currentItem()?.id == item.id {
                        shareable = url
                        print("Video URL for sharing obtained from current player: \(url)")
                    } else { // Fallback if player URL wasn't ready or item changed quickly
                        print("Player URL not available or item mismatch, fetching video URL again for sharing...")
                        if let url = await viewModel.requestVideoURL(for: item.asset) { shareable = url; print("Video URL prepared: \(url)") }
                        else { print("Failed to get video URL for sharing.") }
                    }
                default:
                    print("Unsupported media type for sharing.")
                }
                await MainActor.run {
                    isFetchingShareItem = false
                    if let validItem = shareable {
                        self.itemToShare = ShareableItem(items: [validItem])
                        print("Setting itemToShare to trigger sheet.")
                    } else {
                        print("Failed to prepare item for sharing, not showing sheet.")
                    }
                }
            }
        }
        
    }

    
    // MARK: - Helper Struct for Share Sheet Item (Unchanged)
    struct ShareableItem: Identifiable {
        let id = UUID()
        let items: [Any]
    }
    
    // MARK: - UIActivityViewControllerRepresentable (Unchanged)
    struct ActivityViewControllerRepresentable: UIViewControllerRepresentable {
        var activityItems: [Any]
        var applicationActivities: [UIActivity]? = nil
        func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities) }
        func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
    }

