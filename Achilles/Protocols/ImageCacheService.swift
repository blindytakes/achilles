// Suggested Path: Throwbaks/Achilles/Implementations/ImageCacheService.swift
import UIKit
import Foundation // Needed for NSCache

class ImageCacheService: ImageCacheServiceProtocol {

    // MARK: - Nested Constants (Copied/Adapted from PhotoViewModel)
    // Consider if these should live elsewhere or be passed in via configuration
    private struct CacheConstants {
        // Caching Limits
        static let imageCacheCountLimit: Int = 50 // Thumbnail cache
        static let imageCacheMaxCostMB: Int = 100 // In Megabytes
        static let highResCacheCountLimit: Int = 10
        static let highResCacheMaxCostMB: Int = 500 // In Megabytes

        // Cost Calculation Helpers
        static let bytesPerMegabyte: Int = 1024 * 1024
        static let assumedBytesPerPixel: Int = 4 // For RGBA cost estimation
    }

    // MARK: - Properties (Moved from PhotoViewModel)
    private var imageCache = NSCache<NSString, UIImage>()
    private var highResCache = NSCache<NSString, UIImage>()

    // MARK: - Initialization
    init() {
        // Configure caches using constants
        imageCache.countLimit = CacheConstants.imageCacheCountLimit
        imageCache.totalCostLimit = CacheConstants.imageCacheMaxCostMB * CacheConstants.bytesPerMegabyte
        highResCache.countLimit = CacheConstants.highResCacheCountLimit
        highResCache.totalCostLimit = CacheConstants.highResCacheMaxCostMB * CacheConstants.bytesPerMegabyte
        print("💾 ImageCacheService initialized.")
    }

    // MARK: - ImageCacheServiceProtocol Implementation

    func cacheImage(_ image: UIImage, for assetIdentifier: String, isHighRes: Bool) {
        // Estimate cost based on image dimensions, scale, and assumed bytes per pixel
        // Note: Using CGFloat() conversion for calculation clarity
        let cost = Int(image.size.width * image.size.height * image.scale * CGFloat(CacheConstants.assumedBytesPerPixel))

        if isHighRes {
            // Basic checks before adding to cache (NSCache handles actual limits)
            if highResCache.totalCostLimit > 0 && highResCache.totalCostLimit < cost {
                 print("⚠️ High-res cache limit potentially exceeded by new image cost (\(cost) vs limit \(highResCache.totalCostLimit)). Cache might be cleared.")
            }
            highResCache.setObject(image, forKey: assetIdentifier as NSString, cost: cost)
            print("📦 [SVC] Cached high-res image for asset: \(assetIdentifier), size: \(image.size), cost: \(cost)")
        } else {
             if imageCache.totalCostLimit > 0 && imageCache.totalCostLimit < cost {
                 print("⚠️ Thumbnail cache limit potentially exceeded by new image cost (\(cost) vs limit \(imageCache.totalCostLimit)). Cache might be cleared.")
             }
            imageCache.setObject(image, forKey: assetIdentifier as NSString, cost: cost)
            print("📦 [SVC] Cached thumbnail for asset: \(assetIdentifier), size: \(image.size), cost: \(cost)")
        }
    }

    func cachedImage(for assetIdentifier: String, isHighRes: Bool) -> UIImage? {
        let cache = isHighRes ? highResCache : imageCache
        let cacheName = isHighRes ? "high-res" : "thumbnail"

        // Use object(forKey:) which returns nil if not found
        if let cached = cache.object(forKey: assetIdentifier as NSString) {
            print("✅ [SVC] Using cached \(cacheName) image for asset: \(assetIdentifier)")
            return cached
        }
        // No need for explicit print here, implies not found
        return nil
    }

    func clearCache() {
        print("🧹 [SVC] Clearing image caches...")
        imageCache.removeAllObjects()
        highResCache.removeAllObjects()
        print("🧹 [SVC] Image caches cleared.")
    }
}
