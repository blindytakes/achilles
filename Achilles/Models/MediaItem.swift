import Foundation
import Photos

// --- Data Model
struct MediaItem: Identifiable, Hashable {
    let id: String 
    let asset: PHAsset
}
extension MediaItem {
    init(asset: PHAsset) {
        self.id     = asset.localIdentifier
        self.asset  = asset
    }
}


