// FeaturedSelectorServiceProtocol.swift
//
// This protocol defines the interface for selecting featured items from a collection
// of media items, allowing the app to highlight special content to users.
//
// Key features:
// - Defines a single method to select a featured item from an array of MediaItems
// - Returns an optional MediaItem, acknowledging that selection might not always be possible
// - Abstracts the selection algorithm from consuming components
//
// By using this protocol, the app can:
// - Implement different selection strategies (random, based on quality scores, etc.)
// - Swap selection algorithms without affecting dependent components
// - Test different selection approaches through mock implementations


import Foundation

protocol FeaturedSelectorServiceProtocol {
  func pickFeaturedItem(from items: [MediaItem]) -> MediaItem?
}

