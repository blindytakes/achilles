// MediaItem.swift
//
// This model represents a media item (photo or video) in the app, providing
// a wrapper around the system's PHAsset with additional app-specific functionality.
//
// Key features:
// - Wraps a PHAsset from the Photos framework to represent media items
// - Implements Identifiable protocol using the asset's unique identifier
// - Supports Hashable for collection operations (sets, dictionaries)
// - Provides a convenience initializer that extracts the ID from the asset
//
// The model serves as the core data structure for representing photos and vdeos
// throughout the app, bridging the system's PHAsset representation with
// the app's requirements for list rendering and state management.


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


