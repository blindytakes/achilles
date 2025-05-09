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

class FeaturedSelectorService: FeaturedSelectorServiceProtocol {
  func pickFeaturedItem(from items: [MediaItem]) -> MediaItem? {
    guard !items.isEmpty else { return nil }
    return items.first
  }
}

