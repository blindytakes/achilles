import Foundation

class FeaturedSelectorService: FeaturedSelectorServiceProtocol {
  func pickFeaturedItem(from items: [MediaItem]) -> MediaItem? {
    guard !items.isEmpty else { return nil }
    // ➡️ Replace this stub with your real selection logic:
    //    e.g. sort by clarity score, pick the first video if today has a Live Photo, etc.
    return items.first
  }
}

