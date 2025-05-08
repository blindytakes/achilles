// ImageCacheServiceProtocol.swift
//
// This protocol defines the interface for a caching service that handles
// different types of media assets (images and live photos) to improve app performance.
//
// Key features:
// - Manages separate caches for different image resolutions:
//   - Thumbnail/low-resolution images for grid views
//   - High-resolution images for detailed viewing
// - Supports caching of PHLivePhoto objects for live photo content
// - Provides methods to store and retrieve cached items by asset identifier
// - Includes cache management functionality to clear memory when needed
//
// The protocol enables efficient memory usage by allowing the app to:
// - Avoid redundant loading of the same assets
// - Use appropriate resolution images for different UI contexts
// - Free memory resources when system memory is constrained

import UIKit
import Foundation // Keep if other parts rely on it, though NSCache is Foundation
import Photos // <-- **ADD THIS IMPORT**

protocol ImageCacheServiceProtocol {
    /// Stores an image in the appropriate cache (thumbnail or high-res).
    /// - Parameters:
    ///   - image: The `UIImage` to cache.
    ///   - assetIdentifier: The unique identifier for the PHAsset.
    ///   - isHighRes: Boolean indicating if the image is for the high-resolution cache.
    
    func cacheImage(_ image: UIImage, for assetIdentifier: String, isHighRes: Bool)
    /// Retrieves a cached image for the given identifier.
    /// - Parameters:
    ///   - assetIdentifier: The unique identifier for the PHAsset.
    ///   - isHighRes: Boolean indicating whether to check the high-resolution cache.
    /// - Returns: The cached `UIImage` if found, otherwise `nil`.
    
    func cachedImage(for assetIdentifier: String, isHighRes: Bool) -> UIImage?
    /// Retrieves a cached PHLivePhoto object for the given key (asset identifier).
    /// - Parameter key: The unique identifier for the PHAsset.
    /// - Returns: The cached `PHLivePhoto` if found, otherwise `nil`.

    func cachedLivePhoto(for key: String) -> PHLivePhoto?
    /// - Parameters:
    ///   - livePhoto: The `PHLivePhoto` object to cache.
    ///   - key: The unique identifier for the PHAsset.
    func cacheLivePhoto(_ livePhoto: PHLivePhoto, for key: String)
    
    /// Removes all objects from all managed caches (e.g., UIImage, PHLivePhoto).
    func clearCache()
    /// Retrieves a cached placemark string for the given asset ID, if one exists.
    /// 
    func cachedPlacemark(for assetIdentifier: String) -> String?

    /// Stores a placemark string (e.g. “Central Park, New York, NY”) for the given asset ID.
    func cachePlacemark(_ placemark: String, for assetIdentifier: String)
    
    
}
