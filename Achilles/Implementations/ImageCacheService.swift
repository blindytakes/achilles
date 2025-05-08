// ImageCacheService.swift
//
// This service provides a concrete implementation of the ImageCacheServiceProtocol,
// managing multiple caches for different types of media assets to optimize performance.
//
// Key features:
// - Maintains three separate NSCache instances:
//   - Thumbnail cache: For low-resolution grid display images (100 images, 100MB limit)
//   - High-resolution cache: For detailed view images (15 images, 300MB limit)
//   - Live photo cache: For PHLivePhoto objects (15 items limit)
// - Implements intelligent cost calculation for images based on dimensions
// - Provides methods to store and retrieve assets from appropriate caches
// - Includes comprehensive cache management with memory clearing
// - Features detailed logging for cache operations to aid in debugging
//
// The service balances memory usage with performance by using different
// cache settings for different types of media, prioritizing thumbnails
// for grid performance while limiting high-resolution and live photo storage.


import UIKit
import Foundation // Needed for NSCache
import Photos

class ImageCacheService: ImageCacheServiceProtocol {

    // MARK: - Nested Constants
    private struct CacheConstants {
        // UIImage Cache Limits
        static let imageCacheCountLimit: Int = 100 // Thumbnail cache
        static let imageCacheMaxCostMB: Int = 100 // In Megabytes
        static let highResCacheCountLimit: Int = 15 // High-res UIImage cache
        static let highResCacheMaxCostMB: Int = 300 // In Megabytes

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

    private var placemarkCache = [String:String]()
    
    // MARK: - Initialization
    init() {
        // Configure UIImage caches
        imageCache.countLimit = CacheConstants.imageCacheCountLimit
        imageCache.totalCostLimit = CacheConstants.imageCacheMaxCostMB * CacheConstants.bytesPerMegabyte
        highResCache.countLimit = CacheConstants.highResCacheCountLimit
        highResCache.totalCostLimit = CacheConstants.highResCacheMaxCostMB * CacheConstants.bytesPerMegabyte

        // Configure **NEW** Live Photo cache
        livePhotoCache.countLimit = CacheConstants.livePhotoCacheCountLimit
        print("💾 Also initialized placemark cache")
        print("💾 ImageCacheService initialized with 3 caches (Thumbnails, HighRes Images, Live Photos).")
    }

    // MARK: - ImageCacheServiceProtocol Implementation


    func cacheImage(_ image: UIImage, for assetIdentifier: String, isHighRes: Bool) {
        let cost = Int(image.size.width * image.size.height * image.scale * CGFloat(CacheConstants.assumedBytesPerPixel))
        let cacheToUse = isHighRes ? highResCache : imageCache
        let cacheName = isHighRes ? "high-res" : "thumbnail"

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

    // --- PHLivePhoto Methods  ---

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
    
    func cachedPlacemark(for assetIdentifier: String) -> String? {
        return placemarkCache[assetIdentifier]
    }
    
    func cachePlacemark(_ placemark: String, for assetIdentifier: String) {
        placemarkCache[assetIdentifier] = placemark
        print("📦 [SVC] Cached placemark for asset \(assetIdentifier): “\(placemark)”")
    }

    // --- Clear Cache Method (Updated) ---

    func clearCache() {
        print("🧹 [SVC] Clearing ALL caches (thumbnails, high-res images, live photos)...")
        imageCache.removeAllObjects()
        highResCache.removeAllObjects()
        livePhotoCache.removeAllObjects()
        placemarkCache.removeAll()
        print("🧹 [SVC] All caches cleared.")
    }
}

