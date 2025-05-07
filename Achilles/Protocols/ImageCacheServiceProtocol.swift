// Suggested Path: Throwbaks/Achilles/Protocols/ImageCacheServiceProtocol.swift
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
}
