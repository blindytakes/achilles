import Foundation


enum PageState {
    case idle
    case loading
    case loaded(featured: MediaItem?, grid: [MediaItem]) // Holds prepared data
    case empty
    case error(message: String)
    // Note: No Equatable conformance needed with the updated check below
}
