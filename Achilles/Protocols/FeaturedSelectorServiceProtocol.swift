import Foundation

protocol FeaturedSelectorServiceProtocol {
  /// Returns the “best” featured item (e.g. highest clarity) from the list.
  func pickFeaturedItem(from items: [MediaItem]) -> MediaItem?
}

