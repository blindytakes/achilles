// CollageSourceServiceProtocol.swift
//
// Defines the interface for resolving a collage source (year, place, or
// person) into a concrete list of top-scored MediaItems.  The protocol is
// the only thing CollageViewModel knows about — it doesn't care whether
// the backing store is a live index, a mock, or anything else.
//
// The concrete implementation (CollageSourceService) delegates the heavy
// lifting to PhotoIndexServiceProtocol.  This protocol just defines the
// shape of the call.

import Foundation


protocol CollageSourceServiceProtocol {

    /// Resolve a CollageSourceType into up to `MemoryCollage.maxPhotos`
    /// top-scored MediaItems.
    ///
    /// - Parameter source: Which year / place / person to collage.
    /// - Returns: A fully-resolved MemoryCollage, or nil if the source
    ///            produced zero usable photos.
    func resolve(source: CollageSourceType) async -> MemoryCollage?

    /// The years the user can pick from (delegates to the index).
    func availableYears() -> [Int]

    /// The places the user can pick from (delegates to the index).
    func availablePlaces() -> [String]

    /// The people the user can pick from (delegates to the index).
    func availablePeople() -> [String]
}
