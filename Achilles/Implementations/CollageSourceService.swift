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
            #if DEBUG
            print("📂 CollageSourceService: index not ready, triggering build.")
            #endif
            await indexService.buildIndex()
        }

        // Fetch a larger candidate pool so that each Regenerate can surface
        // different photos rather than always returning the same top-N.
        let candidates: [MediaItem]

        switch source {
        case .year(let year):
            candidates = indexService.topItems(forYear: year, limit: MemoryCollage.candidatePoolSize)
            #if DEBUG
            print("📂 CollageSourceService: year \(year) → \(candidates.count) candidates")
            #endif

        case .place(let place):
            candidates = indexService.topItems(forPlace: place, limit: MemoryCollage.candidatePoolSize)
            #if DEBUG
            print("📂 CollageSourceService: place '\(place)' → \(candidates.count) candidates")
            #endif

        case .person(let person):
            candidates = indexService.topItems(forPerson: person, limit: MemoryCollage.candidatePoolSize)
            #if DEBUG
            print("📂 CollageSourceService: person '\(person)' → \(candidates.count) candidates")
            #endif
        }

        guard !candidates.isEmpty else {
            #if DEBUG
            print("📂 CollageSourceService: no photos found for source \(source).")
            #endif
            return nil
        }

        // Pick the right photo count based on availability: prefer 9 (3×3),
        // fall back to 6 (2×3) or 4 (2×2) if we don't have enough candidates.
        let targetCount = optimalPhotoCount(for: candidates.count)
        let items = Array(candidates.shuffled().prefix(targetCount))

        #if DEBUG
        print("📂 CollageSourceService: selected \(items.count) photos from \(candidates.count) candidates")
        #endif

        return MemoryCollage(
            source:      source,
            items:       items,
            generatedAt: Date()
        )
    }

    // MARK: - Private helpers

    /// Choose the best grid size based on how many photos are available.
    /// Prefers 9 (3×3 grid), falls back to 6 (2×3) or 4 (2×2), otherwise uses
    /// whatever's available.
    private func optimalPhotoCount(for available: Int) -> Int {
        if available >= 9 {
            return 9   // 3×3 grid
        } else if available >= 6 {
            return 6   // 2×3 grid
        } else if available >= 4 {
            return 4   // 2×2 grid
        } else {
            return available  // Use whatever we have
        }
    }

    func availableYears()  -> [Int]    { indexService.availableYears() }
    func availablePlaces() -> [String] { indexService.availablePlaces() }
    func availablePeople() -> [String] { indexService.availablePeople() }
}
