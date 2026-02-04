// MemoryCollage.swift
//
// Defines the core data model for a memory collage. A collage is a collection
// of up to 10 top-scored photos, grouped by a user-selected source type
// (year, place, or person). This is the contract that the index, source
// service, renderer, and view all work against.
//
// CollageSourceType: the three ways a user can generate a collage.
//   - .year(Int)     – all photos from a given calendar year (e.g. 2021)
//   - .place(String) – all photos from a named location (e.g. "Paris")
//   - .person(String)– all photos of a person from a People album
//
// CollageState: mirrors the PageState pattern used throughout the app —
//   idle → loading → loaded/empty/error. Views switch on this to render
//   the appropriate UI.
//
// MemoryCollage: the resolved collage. Holds the source that produced it,
//   the display title, the ordered list of items (max 10), and the
//   timestamp when it was generated.

import Foundation
import Photos


// MARK: - Source Type

/// The dimension along which a collage is generated.
enum CollageSourceType: Equatable {
    /// A full calendar year (e.g. 2022).
    case year(Int)
    /// A named place from the Photos smart albums (e.g. "San Francisco").
    case place(String)
    /// A person from the Photos People album.
    case person(String)

    // MARK: - Display helpers

    /// Human-readable title for the collage header.
    var displayTitle: String {
        switch self {
        case .year(let y):      return "\(y) Collage"
        case .place(let p):     return "\(p) Collage"
        case .person(let name): return "\(name) Collage"
        }
    }

    /// Short label used in analytics and logging.
    var analyticsLabel: String {
        switch self {
        case .year:   return "year"
        case .place:  return "place"
        case .person: return "person"
        }
    }
}


// MARK: - Collage State

/// Loading-state machine for a collage, following the same pattern as PageState.
enum CollageState {
    case idle
    case loading
    case loaded(MemoryCollage)
    case empty                   // Source matched zero photos
    case error(message: String)
}


// MARK: - Resolved Collage

/// A fully-resolved collage ready for rendering or display.
struct MemoryCollage {
    /// The source that produced this collage.
    let source: CollageSourceType
    /// The ordered list of photos in the collage (max 10, best-scored first).
    let items: [MediaItem]
    /// When this collage was generated (used to decide staleness).
    let generatedAt: Date

    // MARK: - Constants
    static let maxPhotos = 10

    // MARK: - Convenience
    var title: String { source.displayTitle }
    var isEmpty: Bool { items.isEmpty }
}
