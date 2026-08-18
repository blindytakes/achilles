// PhotoIndexServiceProtocol.swift
//
// Defines the public interface for the on-device media index. It records
// visible photos and videos for Places and pre-scores photos so collage
// generation can query quickly without re-scoring at runtime.
//
// Responsibilities exposed by this protocol:
//   - Lifecycle:  build the index, check whether it exists / is stale.
//   - Queries:    fetch top-scored items filtered by year, place, or person.
//   - Metadata:   expose available years, places, and people so the UI can
//                 let the user pick a collage source.
//
// The concrete implementation (PhotoIndexService) owns persistence,
// incremental updates via PHPhotoLibraryChangeObserver. None of that leaks
// through this protocol — consumers
// just ask for data.

import Foundation
import Photos


protocol PhotoIndexServiceProtocol {

    // MARK: - Lifecycle

    /// Whether the index has been built at least once (and is in memory).
    var isIndexReady: Bool { get }

    /// Kick off the initial full index build.  No-ops if already built or
    /// currently building.  Callers do not need to await — the index publishes
    /// its readiness through `isIndexReady`.
    func buildIndex() async

    // MARK: - Queries  (all return results sorted by score, descending)

    /// Top-scored **image** assets from a given calendar year.
    /// - Parameters:
    ///   - year:  The calendar year (e.g. 2022).
    ///   - limit: Max number of results.  Defaults to `MemoryCollage.maxPhotos`.
    /// - Returns: Array of MediaItem, best-scored first.  Empty if nothing matches.
    func topItems(forYear year: Int, limit: Int) -> [MediaItem]

    /// Top-scored **image** assets taken at a given place.
    /// The place identifier comes from `availablePlaces()`.
    /// - Parameters:
    ///   - place: The place identifier string.
    ///   - limit: Max number of results.
    /// - Returns: Array of MediaItem, best-scored first.
    func topItems(forPlace place: String, limit: Int) -> [MediaItem]

    /// Top-scored **image** assets of a given person.
    /// The person identifier comes from `availablePeople()`.
    /// - Parameters:
    ///   - person: The person identifier string.
    ///   - limit:  Max number of results.
    /// - Returns: Array of MediaItem, best-scored first.
    func topItems(forPerson person: String, limit: Int) -> [MediaItem]

    // MARK: - Available sources  (what the user can pick from)

    /// Calendar years that have at least one scored photo, sorted descending.
    func availableYears() -> [Int]

    /// Place names that have at least one scored photo, sorted alphabetically.
    func availablePlaces() -> [String]

    /// People names that have at least one scored photo, sorted alphabetically.
    func availablePeople() -> [String]

    /// Countries and territories represented by visible geotagged photos or videos.
    func countryPhotoSummaries(locale: Locale) -> [CountryPhotoSummary]

    /// All visible geotagged photos and videos assigned to a country or territory.
    func items(forCountryCode countryCode: String) -> [MediaItem]

    /// Persist a user correction for a border/ocean geotag. Passing nil clears
    /// the correction and returns the asset to automatic boundary assignment.
    func setCountryOverride(_ countryCode: String?, forAssetID assetID: String) async
}
