// Suggested Path: Throwbaks/Achilles/Protocols/ImageCacheServiceProtocol.swift
import UIKit
import Foundation // Needed for NSCache

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

    /// Removes all objects from both the thumbnail and high-resolution caches.
    func clearCache()
}
