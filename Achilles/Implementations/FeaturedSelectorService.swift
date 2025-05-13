// FeaturedSelectorService.swift
//
// This service provides a concrete implementation of the FeaturedSelectorServiceProtocol,
// determining which media item should be featured from a collection.
//
// Key features:
// - Implements the selector method defined in FeaturedSelectorServiceProtocol
// - Currently uses a simple selection strategy that returns the first item
// - Handles empty collections by returning nil
//
// While the current implementation is straightforward, this service structure
// allows for future enhancement with more sophisticated selection algorithms:
// - Quality-based selection using metadata or image analysis
// - Random selection with weighting factors
// - User preference-based selection


import Foundation
import Photos // Make sure Photos framework is imported

class FeaturedSelectorService: FeaturedSelectorServiceProtocol {

  func pickFeaturedItem(from items: [MediaItem]) -> MediaItem? {
    guard !items.isEmpty else { return nil }

    var bestItem: MediaItem? = nil
    var highestScore: Int = Int.min // Start with the lowest possible score

    for item in items {
      let score = calculateScore(for: item.asset)

      if score > highestScore {
        highestScore = score
        bestItem = item
      }
      // Optional: If scores are equal, you could add a tie-breaking rule,
      // e.g., prefer the more recent one, or just keep the first one encountered.
      // For simplicity, this will keep the first item that achieves the highest score.
    }
    
    // If no item scored positively, or all items were penalized below a threshold,
    // it might still pick one. If all scores are very negative, `bestItem` will be one of those.
    // If you want to fall back to a simple "first" if no item meets a minimum score,
    // you can add that logic here. For now, it picks the highest score found.
    if bestItem == nil && !items.isEmpty {
        // Fallback if somehow no bestItem was selected but items exist (e.g., all scores Int.min)
        // This shouldn't happen with the current scoring unless items is empty, which is guarded.
        // However, as a very robust fallback:
        print("⚠️ FeaturedSelectorService: No item had a score greater than Int.min. Falling back to first item.")
        return items.first
    }

    if let selected = bestItem {
        print("🏆 Featured item selected: \(selected.id) with score: \(highestScore)")
    } else if !items.isEmpty {
        print("⚠️ FeaturedSelectorService: Could not select a best item, but items were available. Defaulting to first.")
        return items.first // Fallback if no item was clearly "best"
    } else {
        print("ℹ️ FeaturedSelectorService: No items to select from.")
    }
    
    return bestItem
  }

  private func calculateScore(for asset: PHAsset) -> Int {
    var score: Int = 0 // Base score

    // 1. Penalize screenshots
    if asset.mediaSubtypes.contains(.photoScreenshot) {
      score -= 100 // Strong penalty
    }

    // 2. Penalize panoramas
    if asset.mediaSubtypes.contains(.photoPanorama) {
      score -= 50 // Moderate penalty
    }

    // --- Other potential factors you could consider (optional additions): ---

    // Bonus for favorited items (if you want to prioritize them)
    // if asset.isFavorite {
    //   score += 20
    // }

    // Slight bonus for regular photos (not video, not live photo - if 'photo' is more desired as featured)
    if asset.mediaType == .image && !asset.mediaSubtypes.contains(.photoLive) {
        score += 5
    }
    
    // Penalize videos slightly if images are preferred for "featured" still photo
    // if asset.mediaType == .video {
    //     score -= 10
    // }

    // You can also consider aspect ratio if you prefer certain shapes for a "featured" image.
    // For example, avoid very wide or very tall aspect ratios if they don't look good as featured.
    // let aspectRatio = asset.pixelWidth > 0 && asset.pixelHeight > 0 ? Double(asset.pixelWidth) / Double(asset.pixelHeight) : 1.0
    // if aspectRatio > 2.5 || aspectRatio < 0.4 { // Very wide or very tall
    //     score -= 15
    // }

    return score
  }
}
