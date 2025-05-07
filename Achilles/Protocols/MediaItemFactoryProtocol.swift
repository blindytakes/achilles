// Path: Throwbaks/Achilles/Protocols/MediaItemFactoryProtocol.swift
import Foundation
import Photos

/// Protocol for creating MediaItem instances from PHAssets.
protocol MediaItemFactoryProtocol {
    /// Creates a MediaItem from the given PHAsset.
    func createMediaItem(from asset: PHAsset) -> MediaItem
}


