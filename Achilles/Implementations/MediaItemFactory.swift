// MediaItemFactory.swift
//
// This struct provides a concrete implementation of the MediaItemFactoryProtocol,
// creating MediaItem instances from PHAssets with a consistent approach.
//
// Key features:
// - Implements the factory method defined in MediaItemFactoryProtocol
// - Currently provides a simple implementation that initializes MediaItems directly
// - Centralizes MediaItem creation logic in one place
//
// While the current implementation is straightforward, this factory pattern
// provides a foundation for future enhancements such as:
// - Adding metadata enrichment when creating MediaItems
// - Filtering or validating assets before conversion
// - Handling special asset types with custom logic

import Foundation
import Photos

struct MediaItemFactory: MediaItemFactoryProtocol {
    /// Creates a MediaItem from the given PHAsset.
    /// - Parameter asset: The PHAsset to convert.
    /// - Returns: A new MediaItem instance.
    func createMediaItem(from asset: PHAsset) -> MediaItem {
        // Currently simple, just initializes MediaItem.
        // Centralizes the creation logic.
        return MediaItem(asset: asset)
    }
}

