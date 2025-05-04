// Suggested Path: Throwbaks/Achilles/Implementations/ImageCacheService.swift
import UIKit
import Foundation // Needed for NSCache
import Photos // <-- **ADD THIS IMPORT**

// Conforms to the UPDATED ImageCacheServiceProtocol
class ImageCacheService: ImageCacheServiceProtocol {

    // MARK: - Nested Constants
    private struct CacheConstants {
        // UIImage Cache Limits
        static let imageCacheCountLimit: Int = 100 // Thumbnail cache (Increased example)
        static let imageCacheMaxCostMB: Int = 100 // In Megabytes
        static let highResCacheCountLimit: Int = 15 // High-res UIImage cache (Increased example)
        static let highResCacheMaxCostMB: Int = 300 // In Megabytes (Increased example)

        // NEW: PHLivePhoto Cache Limits
        static let livePhotoCacheCountLimit: Int = 15 // Keep fewer Live Photos due to size

        // Cost Calculation Helpers
        static let bytesPerMegabyte: Int = 1024 * 1024
        static let assumedBytesPerPixel: Int = 4 // For RGBA cost estimation
    }

    // MARK: - Properties
    private let imageCache = NSCache<NSString, UIImage>()       // For thumbnail UIImages
    private let highResCache = NSCache<NSString, UIImage>()     // For high-res UIImages
    private let livePhotoCache = NSCache<NSString, PHLivePhoto>() // ** NEW: For PHLivePhoto objects **

    // MARK: - Initialization
    init() {
        // Configure UIImage caches
        imageCache.countLimit = CacheConstants.imageCacheCountLimit
        imageCache.totalCostLimit = CacheConstants.imageCacheMaxCostMB * CacheConstants.bytesPerMegabyte
        highResCache.countLimit = CacheConstants.highResCacheCountLimit
        highResCache.totalCostLimit = CacheConstants.highResCacheMaxCostMB * CacheConstants.bytesPerMegabyte

        // Configure **NEW** Live Photo cache
        livePhotoCache.countLimit = CacheConstants.livePhotoCacheCountLimit
        // We'll rely primarily on count limit for Live Photos, setting cost to 0 when adding.
        // livePhotoCache.totalCostLimit = ... // Optionally set a total cost limit

        print("💾 ImageCacheService initialized with 3 caches (Thumbnails, HighRes Images, Live Photos).")
    }

    // MARK: - ImageCacheServiceProtocol Implementation

    // --- UIImage Methods (Mostly Unchanged) ---

    func cacheImage(_ image: UIImage, for assetIdentifier: String, isHighRes: Bool) {
        let cost = Int(image.size.width * image.size.height * image.scale * CGFloat(CacheConstants.assumedBytesPerPixel))
        let cacheToUse = isHighRes ? highResCache : imageCache
        let cacheName = isHighRes ? "high-res" : "thumbnail"

        // Optional: Warning logic can remain if desired
        // if cacheToUse.totalCostLimit > 0 && cacheToUse.totalCostLimit < cost {
        //     print("⚠️ \(cacheName) cache limit potentially exceeded by new image cost (\(cost))...")
        // }

        cacheToUse.setObject(image, forKey: assetIdentifier as NSString, cost: cost)
        print("📦 [SVC] Cached \(cacheName) image for asset: \(assetIdentifier), cost: \(cost)")
    }

    func cachedImage(for assetIdentifier: String, isHighRes: Bool) -> UIImage? {
        let cacheToUse = isHighRes ? highResCache : imageCache
        let cacheName = isHighRes ? "high-res" : "thumbnail"

        if let cached = cacheToUse.object(forKey: assetIdentifier as NSString) {
            print("✅ [SVC] Using cached \(cacheName) image for asset: \(assetIdentifier)")
            return cached
        }
        return nil
    }

    // --- PHLivePhoto Methods (NEW) ---

    func cachedLivePhoto(for key: String) -> PHLivePhoto? {
        let nsKey = key as NSString
        if let cached = livePhotoCache.object(forKey: nsKey) {
            print("✅ [SVC] Using cached Live Photo for asset: \(key)")
            return cached
        }
        return nil
    }

    func cacheLivePhoto(_ livePhoto: PHLivePhoto, for key: String) {
        let nsKey = key as NSString
        // Set cost to 0, relying on countLimit set in init()
        let cost = 0
        livePhotoCache.setObject(livePhoto, forKey: nsKey, cost: cost)
        print("📦 [SVC] Cached Live Photo for asset: \(key), cost: \(cost)")
    }

    // --- Clear Cache Method (Updated) ---

    func clearCache() {
        print("🧹 [SVC] Clearing ALL caches (thumbnails, high-res images, live photos)...")
        imageCache.removeAllObjects()
        highResCache.removeAllObjects()
        livePhotoCache.removeAllObjects() // <-- ** ADDED clearing for the new cache **
        print("🧹 [SVC] All caches cleared.")
    }
}
