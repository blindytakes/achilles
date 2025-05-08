// MediaItemFactoryProtocol.swift
//
// This protocol defines the interface for creating MediaItem instances from PHAssets,
// providing a standardized way to convert system photo library assets into app-specific models.
//
// Key features:
// - Defines a single factory method to transform PHAssets into MediaItems
// - Enables different implementation strategies for MediaItem creation
// - Supports testing through mock implementations
//
// The protocol allows the app to abstract the creation logic for MediaItems,
// making it easier to adapt to changes in the PHAsset API or MediaItem structure
// while maintaining a consistent interface for components that need to convert assets.

import Foundation
import Photos

/// Protocol for creating MediaItem instances from PHAssets.
protocol MediaItemFactoryProtocol {
    /// Creates a MediaItem from the given PHAsset.
    func createMediaItem(from asset: PHAsset) -> MediaItem
}


