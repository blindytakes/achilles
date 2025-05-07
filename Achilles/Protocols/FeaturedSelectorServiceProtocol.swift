import Foundation

protocol FeaturedSelectorServiceProtocol {
  func pickFeaturedItem(from items: [MediaItem]) -> MediaItem?
}

