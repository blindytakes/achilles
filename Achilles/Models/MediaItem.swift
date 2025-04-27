import Foundation
import Photos

// --- Data Model (Assuming this remains the same) ---
struct MediaItem: Identifiable, Hashable {
    let id: String // Use asset local identifier
    let asset: PHAsset
}
extension MediaItem {
    init(asset: PHAsset) {
        self.id     = asset.localIdentifier
        self.asset  = asset
    }
}


