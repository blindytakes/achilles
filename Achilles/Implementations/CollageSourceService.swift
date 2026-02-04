// CollageSourceService.swift
//
// Concrete implementation of CollageSourceServiceProtocol.  A thin query
// layer that translates a CollageSourceType into a call on the
// PhotoIndexService, then wraps the result in a MemoryCollage.
//
// No scoring logic lives here — the index already pre-computed scores.
// This service is purely: "user picked X → ask the index for the best
// photos matching X → package them up."

import Foundation
import Photos


class CollageSourceService: CollageSourceServiceProtocol {

    // MARK: - Dependencies

    private let indexService: PhotoIndexServiceProtocol

    // MARK: - Init

    init(indexService: PhotoIndexServiceProtocol = PhotoIndexService.shared) {
        self.indexService = indexService
    }

    // MARK: - CollageSourceServiceProtocol

    func resolve(source: CollageSourceType) async -> MemoryCollage? {
        // If the index isn't ready yet, wait for it (non-blocking to caller
        // because this whole method is async).
        if !indexService.isIndexReady {
            print("📂 CollageSourceService: index not ready, triggering build.")
            await indexService.buildIndex()
        }

        let items: [MediaItem]

        switch source {
        case .year(let year):
            items = indexService.topItems(forYear: year, limit: MemoryCollage.maxPhotos)
            print("📂 CollageSourceService: year \(year) → \(items.count) items")

        case .place(let place):
            items = indexService.topItems(forPlace: place, limit: MemoryCollage.maxPhotos)
            print("📂 CollageSourceService: place '\(place)' → \(items.count) items")

        case .person(let person):
            items = indexService.topItems(forPerson: person, limit: MemoryCollage.maxPhotos)
            print("📂 CollageSourceService: person '\(person)' → \(items.count) items")
        }

        guard !items.isEmpty else {
            print("📂 CollageSourceService: no photos found for source \(source).")
            return nil
        }

        return MemoryCollage(
            source:      source,
            items:       items,
            generatedAt: Date()
        )
    }

    func availableYears()  -> [Int]    { indexService.availableYears() }
    func availablePlaces() -> [String] { indexService.availablePlaces() }
    func availablePeople() -> [String] { indexService.availablePeople() }
}
