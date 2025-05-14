// FeaturedSelectorService.swift
//
// This service provides a concrete implementation of the FeaturedSelectorServiceProtocol,
// determining which media item should be featured from a collection.
//
// Key features:
// - Implements the selector method defined in FeaturedSelectorServiceProtocol
// - Uses a scoring mechanism to evaluate photos based on various criteria like
//   media subtypes (penalizing screenshots, panoramas), depth effect,
//   resolution, burst status, and aspect ratio.
// - Optimized for performance with metadata-based quality heuristics
// - Selects the item with the highest overall score.
// - Handles empty collections by returning nil.

import Foundation
import Photos
import UIKit

class FeaturedSelectorService: FeaturedSelectorServiceProtocol {

   // --- Define constants for scores and thresholds ---
   private struct ScoringConstants {
       // Penalties
       static let hiddenPenalty = Int.min
       static let screenshotPenalty = -100
       static let panoramaPenalty = -125
       static let lowResolutionPenalty = -50
       static let nonKeyBurstPenalty = -30
       static let likelyBlurryPenalty = -60          // Based on metadata heuristics
       static let tooShortVideoPenalty = -50         // Accidental videos
       
       // Bonuses
       static let depthEffectBonus = 60
       static let regularStillPhotoBonus = 10
       static let keyBurstBonus = 25
       static let faceDetectedBonus = 75             // Big bonus for faces
       static let hdrPhotoBonus = 15                 // HDR photos usually better composed
       static let outdoorBonus = 15                  // Has location data
       static let editedBonus = 70                   // User took time to edit
       
       // Aspect Ratio Scoring
       static let perfectAspectMatchBonus = 50
       static let excellentAspectMatchBonus = 35
       static let goodAspectMatchBonus = 20
       static let commonCameraFormatBonus = 10
       static let neutralAspectScore = 0
       static let poorAspectMatchPenalty = -10
       static let extremeAspectPenalty = -30
       
       // Modern phone screen ranges
       static let modernPhonePortraitMin = 0.44
       static let modernPhonePortraitMax = 0.48
       static let modernPhoneLandscapeMin = 2.1
       static let modernPhoneLandscapeMax = 2.2
       
       // Good match ranges (slightly wider tolerance)
       static let goodPortraitMin = 0.42
       static let goodPortraitMax = 0.5
       static let goodLandscapeMin = 2.0
       static let goodLandscapeMax = 2.3
       
       // Common camera aspect ratios
       static let fourThreeRatio = 1.333    // 4:3
       static let threeTwoRatio = 1.5       // 3:2
       static let squareRatio = 1.0         // 1:1
       static let sixteenNineRatio = 1.778  // 16:9
       
       // Extreme thresholds
       static let extremePanoramaThreshold = 3.0
       static let extremePortraitThreshold = 0.33
       
       // Tolerance for ratio matching
       static let ratioTolerance = 0.05
       
       // Thresholds
       static let minimumFeaturedWorthyScore = 5
       static let minimumResolution = 800
   }

   func pickFeaturedItem(from items: [MediaItem]) -> MediaItem? {
       guard !items.isEmpty else {
           print("ℹ️ FeaturedSelectorService: No items to select from.")
           return nil
       }

       var bestItem: MediaItem? = nil
       var highestScore: Int = Int.min

       for item in items {
           let score = calculateScore(for: item.asset)

           if score > highestScore {
               highestScore = score
               bestItem = item
           }
       }
       
       if let currentBest = bestItem {
           if highestScore < ScoringConstants.minimumFeaturedWorthyScore {
               print("⚠️ FeaturedSelectorService: Score (\(highestScore)) below threshold.")
           }
           print("🏆 Featured item selected: \(currentBest.id) with score: \(highestScore)")
           return currentBest
       }
       
       return nil
   }

   private func calculateScore(for asset: PHAsset) -> Int {
       var score: Int = 0

       // Basic exclusions
       if asset.isHidden { return ScoringConstants.hiddenPenalty }

       // Media type penalties
       if asset.mediaSubtypes.contains(.photoScreenshot) {
           score += ScoringConstants.screenshotPenalty
       }
       if asset.mediaSubtypes.contains(.photoPanorama) {
           score += ScoringConstants.panoramaPenalty
       }
       
       // Quality bonuses
       if asset.mediaSubtypes.contains(.photoDepthEffect) {
           score += ScoringConstants.depthEffectBonus
           score += ScoringConstants.faceDetectedBonus // Portrait mode = faces
       }
       if asset.mediaSubtypes.contains(.photoHDR) {
           score += ScoringConstants.hdrPhotoBonus
       }
       if asset.mediaType == .image && !asset.mediaSubtypes.contains(.photoLive) {
           score += ScoringConstants.regularStillPhotoBonus
       }
       
       // Resolution check
       if asset.pixelWidth < ScoringConstants.minimumResolution ||
          asset.pixelHeight < ScoringConstants.minimumResolution {
           score += ScoringConstants.lowResolutionPenalty
       }

       // Burst photos
       if asset.representsBurst {
           if asset.burstSelectionTypes.contains(.userPick) ||
              asset.burstSelectionTypes.contains(.autoPick) {
               score += ScoringConstants.keyBurstBonus
           } else {
               score += ScoringConstants.nonKeyBurstPenalty
               score += ScoringConstants.likelyBlurryPenalty
           }
       }
       
       // Aspect ratio for full-screen display
       score += calculateAspectRatioScore(asset: asset)
       
       // Video handling
       if asset.mediaType == .video && asset.duration < 2.0 {
           score += ScoringConstants.tooShortVideoPenalty
       }
       
       // Location bonus (outdoor photos)
       if asset.location != nil {
           score += ScoringConstants.outdoorBonus
       }
       
       // Edited photos
       if asset.hasAdjustments {
           score += ScoringConstants.editedBonus
       }

       return score
   }

   private func calculateAspectRatioScore(asset: PHAsset) -> Int {
       guard asset.pixelWidth > 0 && asset.pixelHeight > 0 else { return 0 }
       
       let width = Double(asset.pixelWidth)
       let height = Double(asset.pixelHeight)
       let ratio = width / height
       
       // Check both orientations
       let portraitRatio = min(ratio, 1.0/ratio)
       let landscapeRatio = max(ratio, 1.0/ratio)
       
       // Perfect match for modern phones
       if (portraitRatio >= ScoringConstants.modernPhonePortraitMin &&
           portraitRatio <= ScoringConstants.modernPhonePortraitMax) ||
          (landscapeRatio >= ScoringConstants.modernPhoneLandscapeMin &&
           landscapeRatio <= ScoringConstants.modernPhoneLandscapeMax) {
           return ScoringConstants.perfectAspectMatchBonus
       }
       
       // Excellent match (wider tolerance)
       if (portraitRatio >= ScoringConstants.goodPortraitMin &&
           portraitRatio <= ScoringConstants.goodPortraitMax) ||
          (landscapeRatio >= ScoringConstants.goodLandscapeMin &&
           landscapeRatio <= ScoringConstants.goodLandscapeMax) {
           return ScoringConstants.excellentAspectMatchBonus
       }
       
       // Check common camera formats
       if isCommonCameraFormat(ratio: landscapeRatio) || isCommonCameraFormat(ratio: portraitRatio) {
           return ScoringConstants.commonCameraFormatBonus
       }
       
       // Too extreme (panoramas)
       if landscapeRatio > ScoringConstants.extremePanoramaThreshold ||
          portraitRatio < ScoringConstants.extremePortraitThreshold {
           return ScoringConstants.extremeAspectPenalty
       }
       
       // Everything else
       return ScoringConstants.poorAspectMatchPenalty
   }
   
   private func isCommonCameraFormat(ratio: Double) -> Bool {
       let commonRatios = [
           ScoringConstants.fourThreeRatio,
           ScoringConstants.threeTwoRatio,
           ScoringConstants.squareRatio,
           ScoringConstants.sixteenNineRatio
       ]
       
       for commonRatio in commonRatios {
           if abs(ratio - commonRatio) < ScoringConstants.ratioTolerance {
               return true
           }
       }
       
       return false
   }
}
