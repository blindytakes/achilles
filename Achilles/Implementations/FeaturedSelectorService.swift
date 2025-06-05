// FeaturedSelectorService.swift - Simplified Rewrite
//
// This service implements a simplified, rule-based scoring mechanism
// to quickly determine the best "featured" photo from a collection.
// It prioritizes speed and clarity by focusing on a few high-impact criteria.

import Foundation
import Photos

class FeaturedSelectorService: FeaturedSelectorServiceProtocol {

    // --- Define a simplified set of scoring constants ---
    private struct Scoring {
        // --- Core Bonuses (High Impact) ---
        static let isEditedBonus              = 150 // User invested time in this photo.
        static let hasPeopleBonus             = 300 // Depth Effect is a great proxy for a portrait of people.
        static let isKeyBurstBonus            = 50  // User or system picked this from a burst.

        // --- Contextual Bonuses (Lower Impact) ---
        static let hasGoodAspectRatioBonus    = 20  // Fits well on screen without being an extreme ratio.
        static let hasLocationBonus           = 10  // Adds valuable context to the memory.

        // --- Penalties ---
        static let isScreenshotPenalty        = -500 // Screenshots are rarely featured memories.
        static let hasExtremeAspectRatioPenalty = -200 // Penalizes panoramas, etc.
        static let isLowResolutionPenalty     = -100 // Basic quality check.
        static let isNonKeyBurstPenalty       = -50  // Likely a random, uncurated shot.
        
        // --- Disqualifier ---
        static let isHiddenPenalty            = Int.min // Effectively disqualifies the photo.
        
        // --- Thresholds ---
        static let minimumResolution            = 1500
        static let extremeAspectRatioThreshold  = 2.5 // e.g., wider than 2.5:1
    }

    // In Achilles/Implementations/FeaturedSelectorService.swift

    func pickFeaturedItem(from items: [MediaItem]) -> MediaItem? {
        guard !items.isEmpty else {
            print("ℹ️ FeaturedSelectorService (Simplified): No items to select from.")
            return nil
        }

        // --- 1. Score all items ---
        let scoredItems = items.map { (item: $0, score: calculateScore(for: $0.asset)) }

        // --- 2. Sort by score to find the best and log contenders ---
        let sortedItems = scoredItems.sorted { $0.score > $1.score }
        
        // --- 3. NEW: Log the top contenders for easy debugging ---
        print("--- Featured Item Score Contenders (Top 5) ---")
        for (item, score) in sortedItems.prefix(5) {
            print("  - Item ID: \(item.id), Score: \(score)")
        }
        print("---------------------------------------------")

        // --- 4. Select the best item ---
        guard let bestScoredItem = sortedItems.first else {
            return nil
        }
        
        // If the best score is negative, feature nothing.
        if bestScoredItem.score < 0 {
            print("⚠️ FeaturedSelectorService (Simplified): Best item score is \(bestScoredItem.score). No item is worthy of being featured.")
            return nil
        }

        // Log the final choice
        print("🏆 Featured item selected: \(bestScoredItem.item.id) with score: \(bestScoredItem.score)")
        return bestScoredItem.item
    }

    /// Calculates a score based on a simplified set of rules.
    private func calculateScore(for asset: PHAsset) -> Int {
        // Disqualify hidden photos immediately for speed.
        if asset.isHidden { return Scoring.isHiddenPenalty }
        
        // For simplicity, we will only score images. Videos get a neutral score.
        guard asset.mediaType == .image else { return 0 }

        var score = 0

        // --- 1. Apply strong penalties first ---
        if asset.mediaSubtypes.contains(.photoScreenshot) {
            score += Scoring.isScreenshotPenalty
        }
        if asset.pixelWidth < Scoring.minimumResolution || asset.pixelHeight < Scoring.minimumResolution {
            score += Scoring.isLowResolutionPenalty
        }

        if asset.hasAdjustments {
            score += Scoring.isEditedBonus
        }
        if asset.mediaSubtypes.contains(.photoDepthEffect) {
            score += Scoring.hasPeopleBonus
        }

        // --- 3. Handle specific cases like Bursts ---
        if asset.representsBurst {
            if asset.burstSelectionTypes.contains(.userPick) || asset.burstSelectionTypes.contains(.autoPick) {
                score += Scoring.isKeyBurstBonus
            } else {
                score += Scoring.isNonKeyBurstPenalty
            }
        }
        
        // --- 4. Handle aspect ratio ---
        let width = Double(asset.pixelWidth)
        let height = Double(asset.pixelHeight)
        if width > 0 && height > 0 {
            let ratio = max(width, height) / min(width, height)
            if ratio > Scoring.extremeAspectRatioThreshold {
                score += Scoring.hasExtremeAspectRatioPenalty
            } else {
                score += Scoring.hasGoodAspectRatioBonus
            }
        }

        // --- 5. Apply minor contextual bonus ---
        if asset.location != nil {
            score += Scoring.hasLocationBonus
        }

        return score
    }
}
