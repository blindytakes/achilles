// Path: Throwbaks/Achilles/Implementations/MediaItemFactory.swift
import Foundation
import Photos

/// Concrete implementation of the MediaItemFactoryProtocol.
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

