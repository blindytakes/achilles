// PhotoIndexService.swift
//
// The on-device photo index. Pre-scores every image in the user's library
// once, persists the result, and keeps it incrementally up-to-date via
// PHPhotoLibraryChangeObserver. A monthly full rebuild runs silently in
// the background as a safety net.
//
// Architecture at a glance
// ─────────────────────────
//   IndexEntry          – the ~26-byte scored snapshot of one PHAsset.
//   PhotoIndexService   – owns the in-memory index, persistence, change
//                          observation, and all public queries.
//
// Persistence
//   The index is serialised as a [String: IndexEntry] dictionary to a
//   JSON file in the app's cache directory.  A version tag is included so
//   that schema changes trigger an automatic rebuild on next launch.
//
// Scoring
//   Delegates to the same logic used by FeaturedSelectorService.  The
//   score is cached in IndexEntry so queries never re-score.
//
// Threading
//   - buildIndex / rebuildIfNeeded run on a detached background task.
//   - All writes to the in-memory dictionary are serialised through
//     a single background serial queue.
//   - Query methods (topItems, available*) read a snapshot of the
//     dictionary on the caller's thread — safe because Swift Dictionary
//     is a value type and the snapshot is taken under the serial queue.

import Foundation
import Photos


// MARK: - Index Entry

/// A lightweight, Codable snapshot of a single PHAsset's scoring inputs
/// and pre-computed score.  This is what gets persisted to disk.
struct IndexEntry: Codable {
    let assetId: String           // PHAsset.localIdentifier

    // Scoring inputs (mirrors what FeaturedSelectorService reads)
    let mediaType: UInt8          // PHAssetMediaType raw value
    let isHidden: Bool
    let isScreenshot: Bool
    let hasDepthEffect: Bool
    let hasAdjustments: Bool
    let representsBurst: Bool
    let burstHasUserPick: Bool
    let burstHasAutoPick: Bool
    let pixelWidth: UInt16
    let pixelHeight: UInt16
    let hasLocation: Bool
    let latitude: Float?          // nil when hasLocation == false
    let longitude: Float?

    // Derived / cached
    let creationYear: Int         // Calendar year of creationDate
    let score: Int                // Pre-computed quality score
}


// MARK: - PhotoIndexService

class PhotoIndexService: NSObject, PhotoIndexServiceProtocol, PHPhotoLibraryChangeObserver {

    // MARK: - Constants

    private struct Constants {
        /// Bump this when IndexEntry schema changes.  Mismatch → full rebuild.
        static let persistenceVersion: Int = 1

        /// Rebuild the full index if it hasn't been rebuilt in this many days.
        static let monthlyRebuildDays: Int = 30

        /// UserDefaults keys
        static let lastRebuildDateKey  = "PhotoIndex.lastRebuildDate"
        static let persistenceVersionKey = "PhotoIndex.persistenceVersion"

        /// Cache-directory filename for the persisted index.
        static let indexFileName = "photo_index.json"

        /// Scoring constants — kept in sync with FeaturedSelectorService.
        struct Scoring {
            static let isEditedBonus              = 150
            static let hasPeopleBonus             = 300
            static let isKeyBurstBonus            = 50
            static let hasGoodAspectRatioBonus    = 20
            static let hasLocationBonus           = 10
            static let isScreenshotPenalty        = -500
            static let hasExtremeAspectRatioPenalty = -200
            static let isLowResolutionPenalty     = -100
            static let isNonKeyBurstPenalty       = -50
            static let isHiddenPenalty            = Int.min
            static let minimumResolution          = 1500
            static let extremeAspectRatioThreshold: Double = 2.5
        }
    }

    // MARK: - Properties

    /// Thread-safe access gate for the in-memory index.
    private let queue = DispatchQueue(label: "com.throwbaks.PhotoIndexService", qos: .userInitiated)

    /// The in-memory index.  Only mutated on `queue`.
    private var _index: [String: IndexEntry] = [:]

    /// Whether the index has completed at least one build.
    private var _isReady = false

    /// Guard against concurrent builds.
    private var _isBuildingIndex = false

    // MARK: - Protocol conformance – computed

    var isIndexReady: Bool {
        queue.sync { _isReady }
    }

    // MARK: - Singleton

    static let shared = PhotoIndexService()

    // MARK: - Initialisation

    private override init() {
        super.init()
        // Register for photo-library changes so incremental updates work.
        PHPhotoLibrary.shared().register(self)
        print("📇 PhotoIndexService: initialised, registered as change observer.")
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
        print("📇 PhotoIndexService: deinit, unregistered change observer.")
    }

    // MARK: - Lifecycle  (PhotoIndexServiceProtocol)

    func buildIndex() async {
        // If already ready and not stale, nothing to do.
        let alreadyReady = queue.sync { _isReady }
        if alreadyReady {
            print("📇 PhotoIndexService: index already built, skipping buildIndex().")
            return
        }

        // Try to load a valid persisted index first (fast path).
        if await loadPersistedIndex() {
            print("📇 PhotoIndexService: loaded valid persisted index.")
            return
        }

        // Cold start – build from scratch.
        print("📇 PhotoIndexService: no valid persisted index found, performing full build.")
        await performFullBuild()
    }

    func rebuildIfNeeded() async {
        let lastRebuild = UserDefaults.standard.object(forKey: Constants.lastRebuildDateKey) as? Date ?? .distantPast
        let daysSinceRebuild = Calendar.current.dateComponents([.day], from: lastRebuild, to: Date()).day ?? Int.max

        if daysSinceRebuild >= Constants.monthlyRebuildDays {
            print("📇 PhotoIndexService: monthly rebuild due (\(daysSinceRebuild) days since last). Rebuilding.")
            await performFullBuild()
        } else {
            print("📇 PhotoIndexService: rebuild not due yet (\(daysSinceRebuild) days since last).")
        }
    }

    // MARK: - Queries  (PhotoIndexServiceProtocol)

    func topItems(forYear year: Int, limit: Int = MemoryCollage.maxPhotos) -> [MediaItem] {
        let snapshot = queue.sync { _index }
        let matched = snapshot.values
            .filter { $0.creationYear == year && $0.mediaType == PHAssetMediaType.image.rawValue && !$0.isHidden }
            .sorted { $0.score > $1.score }
            .prefix(limit)

        return resolveMediaItems(from: Array(matched))
    }

    func topItems(forPlace place: String, limit: Int = MemoryCollage.maxPhotos) -> [MediaItem] {
        // Fetch the asset IDs that belong to this place via PHAssetCollection,
        // then cross-reference with the index for scoring + sorting.
        guard let collection = findSmartAlbum(named: place) else {
            print("📇 PhotoIndexService: no smart album found for place '\(place)'.")
            return []
        }

        let assetIDs = fetchAssetIDs(from: collection)
        let snapshot = queue.sync { _index }

        let matched = assetIDs.compactMap { snapshot[$0] }
            .filter { $0.mediaType == PHAssetMediaType.image.rawValue && !$0.isHidden }
            .sorted { $0.score > $1.score }
            .prefix(limit)

        return resolveMediaItems(from: Array(matched))
    }

    func topItems(forPerson person: String, limit: Int = MemoryCollage.maxPhotos) -> [MediaItem] {
        guard let collection = findPeopleAlbum(named: person) else {
            print("📇 PhotoIndexService: no People album found for '\(person)'.")
            return []
        }

        let assetIDs = fetchAssetIDs(from: collection)
        let snapshot = queue.sync { _index }

        let matched = assetIDs.compactMap { snapshot[$0] }
            .filter { $0.mediaType == PHAssetMediaType.image.rawValue && !$0.isHidden }
            .sorted { $0.score > $1.score }
            .prefix(limit)

        return resolveMediaItems(from: Array(matched))
    }

    // MARK: - Available sources  (PhotoIndexServiceProtocol)

    func availableYears() -> [Int] {
        let snapshot = queue.sync { _index }
        let years = Set(
            snapshot.values
                .filter { $0.mediaType == PHAssetMediaType.image.rawValue && !$0.isHidden }
                .map { $0.creationYear }
        )
        return years.sorted(by: >)   // Most recent first
    }

    func availablePlaces() -> [String] {
        // Location-based smart albums: raw value 66 = smartAlbumByLocation
        // (not a named symbol on all SDK versions).
        guard let locationSubtype = PHAssetCollectionSubtype(rawValue: 66) else { return [] }
        let results = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: locationSubtype,
            options: nil
        )
        var places = [String]()
        results.enumerateObjects { collection, _, _ in
            guard let title = collection.localizedTitle, !title.isEmpty else { return }
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            if assets.count > 0 { places.append(title) }
        }
        return Array(Set(places)).sorted()
    }

    func availablePeople() -> [String] {
        // People smart album: raw value 54 = smartAlbumFacesWithPeople
        // (not a named symbol on all SDK versions).
        guard let peopleSubtype = PHAssetCollectionSubtype(rawValue: 54) else { return [] }
        let results = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: peopleSubtype,
            options: nil
        )
        var people = [String]()
        results.enumerateObjects { collection, _, _ in
            guard let title = collection.localizedTitle, !title.isEmpty else { return }
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            if assets.count > 0 { people.append(title) }
        }
        return people.sorted()
    }

    // MARK: - PHPhotoLibraryChangeObserver

    func photoLibraryDidChange(_ changeInfo: PHChange) {
        print("📇 PhotoIndexService: PHPhotoLibrary change detected, performing incremental update.")
        // Run the incremental update on our serial queue so it doesn't race
        // with a concurrent full build.
        queue.async { [weak self] in
            self?.applyIncrementalUpdate(changeInfo)
        }
    }

    // MARK: - Private – Full Build

    private func performFullBuild() async {
        // Guard against concurrent builds.
        let alreadyBuilding = queue.sync {
            if _isBuildingIndex { return true }
            _isBuildingIndex = true
            return false
        }
        guard !alreadyBuilding else {
            print("📇 PhotoIndexService: build already in progress, skipping.")
            return
        }

        let spanStart = Date()
        print("📇 PhotoIndexService: ── full build START ──")

        // Fetch ALL image assets.  PHAsset.fetchAssets is synchronous but
        // fast (it's a SQLite query against Apple's index).
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "isHidden == NO")
        // Include images only for scoring; videos get score 0 in
        // FeaturedSelectorService anyway.
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue),
            NSPredicate(format: "isHidden == NO")
        ])

        let fetchResult = PHAsset.fetchAssets(with: options)
        print("📇 PhotoIndexService: fetched \(fetchResult.count) image assets.")

        // Score every asset.  This is CPU-bound but each score is O(1) —
        // just reading a handful of properties and doing arithmetic.
        var newIndex = [String: IndexEntry]()
        newIndex.reserveCapacity(fetchResult.count)

        fetchResult.enumerateObjects { asset, _, _ in
            let entry = self.buildEntry(for: asset)
            newIndex[entry.assetId] = entry
        }

        // Swap in the new index and mark ready.
        queue.sync {
            self._index = newIndex
            self._isReady = true
            self._isBuildingIndex = false
        }

        let durationMs = Int(Date().timeIntervalSince(spanStart) * 1000)
        print("📇 PhotoIndexService: ── full build DONE ── \(newIndex.count) entries in \(durationMs) ms")

        // Persist to disk (fire-and-forget; non-critical path).
        persistIndex()

        // Record the rebuild timestamp.
        UserDefaults.standard.set(Date(), forKey: Constants.lastRebuildDateKey)

        // Telemetry
        TelemetryService.shared.recordSpan(
            name: "photoIndex.fullBuild",
            startTime: spanStart,
            durationMs: durationMs,
            attributes: ["entry_count": newIndex.count]
        )
        TelemetryService.shared.recordHistogram(
            name: "throwbaks.photoIndex.buildDuration",
            value: Double(durationMs)
        )
        TelemetryService.shared.log(
            "photoIndex full build complete",
            attributes: ["entry_count": newIndex.count, "duration_ms": durationMs]
        )
    }

    // MARK: - Private – Incremental Update

    /// Walks the PHChange tree looking for asset-level changes (adds,
    /// removes, updates) and patches only those entries.
    private func applyIncrementalUpdate(_ changeInfo: PHChange) {
        // We need to snapshot the current fetch result so PHChange can
        // give us a diff.  Re-fetch with the same options as the full build.
        let options = PHFetchOptions()
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue),
            NSPredicate(format: "isHidden == NO")
        ])
        let fetchResult = PHAsset.fetchAssets(with: options)

        guard let changes = changeInfo.changeDetails(for: fetchResult) else {
            print("📇 PhotoIndexService: no asset-level changes detected.")
            return
        }

        var added   = 0
        var removed = 0
        var updated = 0

        let afterResult = changes.fetchResultAfterChanges

        // ── Removed ──
        if let removedIndexes = changes.removedIndexes, removedIndexes.count > 0 {
            // Removed assets no longer exist — we can't fetch them.
            // Walk the *before* result to collect their IDs.
            let beforeResult = changes.fetchResultBeforeChanges
            var removedIDs = Set<String>()
            removedIndexes.forEach { idx in
                let asset = beforeResult.object(at: idx)
                removedIDs.insert(asset.localIdentifier)
            }
            _index = _index.filter { !removedIDs.contains($0.key) }
            removed = removedIDs.count
        }

        // ── Added ──
        if let insertedIndexes = changes.insertedIndexes, insertedIndexes.count > 0 {
            insertedIndexes.forEach { idx in
                let asset = afterResult.object(at: idx)
                let entry = buildEntry(for: asset)
                _index[entry.assetId] = entry
            }
            added = insertedIndexes.count
        }

        // ── Updated (e.g. edited, location changed) ──
        if let changedIndexes = changes.changedIndexes, changedIndexes.count > 0 {
            changedIndexes.forEach { idx in
                let asset = afterResult.object(at: idx)
                let entry = buildEntry(for: asset)
                _index[entry.assetId] = entry
            }
            updated = changedIndexes.count
        }

        if added + removed + updated > 0 {
            print("📇 PhotoIndexService: incremental update — +\(added) -\(removed) ~\(updated)")
            // Re-persist after any mutation.
            persistIndex()
        }
    }

    // MARK: - Private – Scoring

    /// Build an IndexEntry for a single PHAsset using the same scoring
    /// logic as FeaturedSelectorService.
    private func buildEntry(for asset: PHAsset) -> IndexEntry {
        let year = asset.creationDate.map { Calendar.current.component(.year, from: $0) } ?? 0

        let loc = asset.location
        let lat: Float? = loc.map { Float($0.coordinate.latitude) }
        let lon: Float? = loc.map { Float($0.coordinate.longitude) }

        let entry = IndexEntry(
            assetId:          asset.localIdentifier,
            mediaType:        UInt8(asset.mediaType.rawValue),
            isHidden:         asset.isHidden,
            isScreenshot:     asset.mediaSubtypes.contains(.photoScreenshot),
            hasDepthEffect:   asset.mediaSubtypes.contains(.photoDepthEffect),
            hasAdjustments:   asset.hasAdjustments,
            representsBurst:  asset.representsBurst,
            burstHasUserPick: asset.burstSelectionTypes.contains(.userPick),
            burstHasAutoPick: asset.burstSelectionTypes.contains(.autoPick),
            pixelWidth:       UInt16(clamping: asset.pixelWidth),
            pixelHeight:      UInt16(clamping: asset.pixelHeight),
            hasLocation:      loc != nil,
            latitude:         lat,
            longitude:        lon,
            creationYear:     year,
            score:            calculateScore(for: asset)
        )
        return entry
    }

    /// Pure scoring function — mirrors FeaturedSelectorService.calculateScore.
    private func calculateScore(for asset: PHAsset) -> Int {
        if asset.isHidden { return Constants.Scoring.isHiddenPenalty }
        guard asset.mediaType == .image else { return 0 }

        var score = 0

        if asset.mediaSubtypes.contains(.photoScreenshot) {
            score += Constants.Scoring.isScreenshotPenalty
        }
        if asset.pixelWidth  < Constants.Scoring.minimumResolution ||
           asset.pixelHeight < Constants.Scoring.minimumResolution {
            score += Constants.Scoring.isLowResolutionPenalty
        }
        if asset.hasAdjustments {
            score += Constants.Scoring.isEditedBonus
        }
        if asset.mediaSubtypes.contains(.photoDepthEffect) {
            score += Constants.Scoring.hasPeopleBonus
        }
        if asset.representsBurst {
            if asset.burstSelectionTypes.contains(.userPick) ||
               asset.burstSelectionTypes.contains(.autoPick) {
                score += Constants.Scoring.isKeyBurstBonus
            } else {
                score += Constants.Scoring.isNonKeyBurstPenalty
            }
        }

        let w = Double(asset.pixelWidth)
        let h = Double(asset.pixelHeight)
        if w > 0 && h > 0 {
            let ratio = max(w, h) / min(w, h)
            if ratio > Constants.Scoring.extremeAspectRatioThreshold {
                score += Constants.Scoring.hasExtremeAspectRatioPenalty
            } else {
                score += Constants.Scoring.hasGoodAspectRatioBonus
            }
        }

        if asset.location != nil {
            score += Constants.Scoring.hasLocationBonus
        }

        return score
    }

    // MARK: - Private – Persistence

    /// Path to the persisted index file in the app's cache directory.
    private var indexFilePath: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent(Constants.indexFileName)
    }

    /// Serialise the current index to disk.  Non-blocking – runs on a
    /// background thread and is fire-and-forget.
    private func persistIndex() {
        // Take a snapshot under the queue so we don't race.
        let snapshot = queue.sync { _index }

        DispatchQueue.global(qos: .background).async {
            do {
                let wrapper: [String: Any] = [
                    "version": Constants.persistenceVersion,
                    "entries": snapshot
                ]
                let data = try JSONSerialization.data(withJSONObject: wrapper)
                try data.write(to: self.indexFilePath)
                print("📇 PhotoIndexService: persisted \(snapshot.count) entries to disk.")
            } catch {
                print("❌ PhotoIndexService: failed to persist index – \(error.localizedDescription)")
            }
        }
    }

    /// Attempt to load a previously persisted index.  Returns `true` if
    /// successful and the version matches; `false` otherwise (caller should
    /// do a full build).
    @discardableResult
    private func loadPersistedIndex() async -> Bool {
        guard FileManager.default.fileExists(atPath: indexFilePath.path) else {
            print("📇 PhotoIndexService: no persisted index file found.")
            return false
        }

        do {
            let data = try Data(contentsOf: indexFilePath)
            guard let wrapper = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = wrapper["version"] as? Int,
                  version == Constants.persistenceVersion,
                  let entriesRaw = wrapper["entries"] as? [String: Any] else {
                print("📇 PhotoIndexService: persisted index version mismatch or corrupt. Will rebuild.")
                return false
            }

            // Re-encode just the entries portion so we can decode via Codable.
            let entriesData = try JSONSerialization.data(withJSONObject: entriesRaw)
            let entries = try JSONDecoder().decode([String: IndexEntry].self, from: entriesData)

            queue.sync {
                self._index = entries
                self._isReady = true
            }

            print("📇 PhotoIndexService: loaded \(entries.count) entries from persisted index (v\(version)).")
            return true
        } catch {
            print("❌ PhotoIndexService: failed to load persisted index – \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private – PHAssetCollection helpers

    /// Find a location-based smart album by its localised title.
    private func findSmartAlbum(named title: String) -> PHAssetCollection? {
        let results = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: PHAssetCollectionSubtype(rawValue: 66)!,
            options: nil
        )
        var found: PHAssetCollection?
        results.enumerateObjects { collection, _, stop in
            if collection.localizedTitle == title {
                found = collection
                stop.pointee = true
            }
        }
        return found
    }

    /// Find a People smart album by its localised title.
    private func findPeopleAlbum(named title: String) -> PHAssetCollection? {
        let results = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: PHAssetCollectionSubtype(rawValue: 54)!,
            options: nil
        )
        var found: PHAssetCollection?
        results.enumerateObjects { collection, _, stop in
            if collection.localizedTitle == title {
                found = collection
                stop.pointee = true
            }
        }
        return found
    }

    /// Pull all asset local-identifiers out of a collection.
    private func fetchAssetIDs(from collection: PHAssetCollection) -> [String] {
        let assets = PHAsset.fetchAssets(in: collection, options: nil)
        var ids = [String]()
        ids.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in
            ids.append(asset.localIdentifier)
        }
        return ids
    }

    // MARK: - Private – MediaItem resolution

    /// Given a set of IndexEntry values, fetch the live PHAssets and wrap
    /// them as MediaItems.  Entries whose asset no longer exists are silently
    /// dropped.
    private func resolveMediaItems(from entries: [IndexEntry]) -> [MediaItem] {
        guard !entries.isEmpty else { return [] }

        let ids = entries.map { $0.assetId }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)

        // Build a lookup so we can return items in score order (not fetch order).
        var assetMap = [String: PHAsset]()
        assetMap.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in
            assetMap[asset.localIdentifier] = asset
        }

        // Walk entries in their original (score-sorted) order.
        return entries.compactMap { entry in
            guard let asset = assetMap[entry.assetId] else { return nil }
            return MediaItem(asset: asset)
        }
    }
}
