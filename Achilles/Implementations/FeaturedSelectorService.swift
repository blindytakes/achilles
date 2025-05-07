import Foundation

class FeaturedSelectorService: FeaturedSelectorServiceProtocol {
  func pickFeaturedItem(from items: [MediaItem]) -> MediaItem? {
    guard !items.isEmpty else { return nil }
    return items.first
  }
}

