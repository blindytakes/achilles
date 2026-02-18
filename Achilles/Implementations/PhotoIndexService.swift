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
import CoreLocation


// MARK: - Persistence Wrapper

/// Top-level envelope persisted to disk.  The `version` field lets us
/// detect schema changes and trigger a rebuild automatically.
private struct IndexPersistencePayload: Codable {
    let version: Int
    let entries: [String: IndexEntry]
}


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

        /// Cache-directory filename for persisted geocode results.
        static let geocodeCacheFileName = "geocode_cache.json"

        /// Scoring constants — kept in sync with FeaturedSelectorService.
        struct Scoring {
            static let isEditedBonus              = 150
            /// Bonus for portrait-mode (depth-effect) photos.  These tend to
            /// be higher-effort shots; note this does NOT confirm a person is
            /// present — it's a quality proxy.
            static let hasDepthEffectBonus        = 300
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

    /// Cached place names derived from reverse-geocoding index coordinates.
    /// Populated during index build, BEFORE _isReady is set.
    private var _cachedPlaces: [String] = []

    /// Mapping from place name → set of asset IDs at that location.
    /// Used by topItems(forPlace:) to find photos at a given place.
    private var _placeToAssetIDs: [String: Set<String>] = [:]

    /// Cached people names derived from the Photos People album.
    private var _cachedPeople: [String] = []

    /// Notification posted (on main thread) when the index finishes building
    /// and place/people caches are populated.  The ViewModel observes this
    /// to update its @Published properties.
    static let indexDidFinishBuilding = Notification.Name("PhotoIndexService.indexDidFinishBuilding")

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
#if DEBUG
        print("📇 PhotoIndexService: initialised, registered as change observer.")
#endif
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
#if DEBUG
        print("📇 PhotoIndexService: deinit, unregistered change observer.")
#endif
    }

    // MARK: - Lifecycle  (PhotoIndexServiceProtocol)

    func buildIndex() async {
        // If already ready and not stale, nothing to do.
        let alreadyReady = queue.sync { _isReady }
        if alreadyReady {
#if DEBUG
            print("📇 PhotoIndexService: index already built, skipping buildIndex().")
#endif
            return
        }

        // Try to load a valid persisted index first (fast path).
        if await loadPersistedIndex() {
#if DEBUG
            print("📇 PhotoIndexService: loaded valid persisted index.")
#endif
            return
        }

        // Cold start – build from scratch.
#if DEBUG
        print("📇 PhotoIndexService: no valid persisted index found, performing full build.")
#endif
        await performFullBuild()
    }

    func rebuildIfNeeded() async {
        let lastRebuild = UserDefaults.standard.object(forKey: Constants.lastRebuildDateKey) as? Date ?? .distantPast
        let daysSinceRebuild = Calendar.current.dateComponents([.day], from: lastRebuild, to: Date()).day ?? Int.max

        if daysSinceRebuild >= Constants.monthlyRebuildDays {
#if DEBUG
            print("📇 PhotoIndexService: monthly rebuild due (\(daysSinceRebuild) days since last). Rebuilding.")
#endif
            await performFullBuild()
        } else {
#if DEBUG
            print("📇 PhotoIndexService: rebuild not due yet (\(daysSinceRebuild) days since last).")
#endif
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
        let (snapshot, assetIDs) = queue.sync { (_index, _placeToAssetIDs[place] ?? []) }

        guard !assetIDs.isEmpty else {
#if DEBUG
            print("📇 PhotoIndexService: no assets mapped to place '\(place)'.")
#endif
            return []
        }

        let matched = assetIDs.compactMap { snapshot[$0] }
            .filter { $0.mediaType == PHAssetMediaType.image.rawValue && !$0.isHidden }
            .sorted { $0.score > $1.score }
            .prefix(limit)

        return resolveMediaItems(from: Array(matched))
    }

    func topItems(forPerson person: String, limit: Int = MemoryCollage.maxPhotos) -> [MediaItem] {
        guard let collection = findPeopleAlbumDocumented(named: person) else {
#if DEBUG
            print("📇 PhotoIndexService: no People album found for '\(person)'.")
#endif
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
        queue.sync { _cachedPlaces }
    }

    func availablePeople() -> [String] {
        queue.sync { _cachedPeople }
    }

    // MARK: - PHPhotoLibraryChangeObserver

    func photoLibraryDidChange(_ changeInfo: PHChange) {
#if DEBUG
        print("📇 PhotoIndexService: PHPhotoLibrary change detected, performing incremental update.")
#endif
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
#if DEBUG
            print("📇 PhotoIndexService: build already in progress, skipping.")
#endif
            return
        }

        let spanStart = Date()
#if DEBUG
        print("📇 PhotoIndexService: ── full build START ──")
#endif

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
#if DEBUG
        print("📇 PhotoIndexService: fetched \(fetchResult.count) image assets.")
#endif

        // Score every asset.  This is CPU-bound but each score is O(1) —
        // just reading a handful of properties and doing arithmetic.
        var newIndex = [String: IndexEntry]()
        newIndex.reserveCapacity(fetchResult.count)

        fetchResult.enumerateObjects { asset, _, _ in
            let entry = self.buildEntry(for: asset)
            newIndex[entry.assetId] = entry
        }

        // Swap in the new index (but DON'T mark ready yet — caches first).
        queue.sync {
            self._index = newIndex
        }

        // Build place & people caches BEFORE marking ready, so that any
        // reader that checks isIndexReady will see populated caches.
        await buildPlacesCache()
        buildPeopleCache()

        // NOW mark ready and allow builds again.
        queue.sync {
            self._isReady = true
            self._isBuildingIndex = false
        }

        let durationMs = Int(Date().timeIntervalSince(spanStart) * 1000)
#if DEBUG
        print("📇 PhotoIndexService: ── full build DONE ── \(newIndex.count) entries in \(durationMs) ms")
#endif

        // Notify observers (ViewModel) that data is available.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.indexDidFinishBuilding, object: nil)
        }

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
#if DEBUG
            print("📇 PhotoIndexService: no asset-level changes detected.")
#endif
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
#if DEBUG
            print("📇 PhotoIndexService: incremental update — +\(added) -\(removed) ~\(updated)")
#endif
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
            score += Constants.Scoring.hasDepthEffectBonus
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

    /// Path to the persisted geocode cache file.
    private var geocodeCacheFilePath: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent(Constants.geocodeCacheFileName)
    }

    /// Load previously geocoded bucket→city mappings from disk.
    /// Key format: "latBucket,lngBucket" (e.g. "407,-740").
    private func loadGeocodeCache() -> [String: String] {
        guard FileManager.default.fileExists(atPath: geocodeCacheFilePath.path) else { return [:] }
        do {
            let data = try Data(contentsOf: geocodeCacheFilePath)
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
#if DEBUG
            print("📇 PhotoIndexService: failed to load geocode cache – \(error.localizedDescription)")
#endif
            return [:]
        }
    }

    /// Persist geocoded bucket→city mappings to disk.
    private func saveGeocodeCache(_ cache: [String: String]) {
        DispatchQueue.global(qos: .background).async {
            do {
                let data = try JSONEncoder().encode(cache)
                try data.write(to: self.geocodeCacheFilePath)
#if DEBUG
                print("📇 PhotoIndexService: persisted geocode cache with \(cache.count) entries.")
#endif
            } catch {
#if DEBUG
                print("❌ PhotoIndexService: failed to persist geocode cache – \(error.localizedDescription)")
#endif
            }
        }
    }

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
                let payload = IndexPersistencePayload(
                    version: Constants.persistenceVersion,
                    entries: snapshot
                )
                let data = try JSONEncoder().encode(payload)
                try data.write(to: self.indexFilePath)
#if DEBUG
                print("📇 PhotoIndexService: persisted \(snapshot.count) entries to disk.")
#endif
            } catch {
#if DEBUG
                print("❌ PhotoIndexService: failed to persist index – \(error.localizedDescription)")
#endif
            }
        }
    }

    /// Attempt to load a previously persisted index.  Returns `true` if
    /// successful and the version matches; `false` otherwise (caller should
    /// do a full build).
    @discardableResult
    private func loadPersistedIndex() async -> Bool {
        guard FileManager.default.fileExists(atPath: indexFilePath.path) else {
#if DEBUG
            print("📇 PhotoIndexService: no persisted index file found.")
#endif
            return false
        }

        do {
            let data = try Data(contentsOf: indexFilePath)
            let payload = try JSONDecoder().decode(IndexPersistencePayload.self, from: data)

            guard payload.version == Constants.persistenceVersion else {
#if DEBUG
                print("📇 PhotoIndexService: persisted index version mismatch (on-disk: \(payload.version), expected: \(Constants.persistenceVersion)). Will rebuild.")
#endif
                return false
            }

            // Load the index entries (but DON'T mark ready yet).
            queue.sync {
                self._index = payload.entries
            }

            // Build caches BEFORE marking ready.
            await buildPlacesCache()
            buildPeopleCache()

            // NOW mark ready.
            queue.sync {
                self._isReady = true
            }

            // Notify observers (ViewModel) that data is available.
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.indexDidFinishBuilding, object: nil)
            }

#if DEBUG
            print("📇 PhotoIndexService: loaded \(payload.entries.count) entries from persisted index (v\(payload.version)).")
#endif
            return true
        } catch {
#if DEBUG
            print("❌ PhotoIndexService: failed to load persisted index – \(error.localizedDescription)")
#endif
            return false
        }
    }

    // MARK: - Private – Place Cache (Reverse Geocoding)

    /// Clusters index entries by rounded lat/lng (~10 km), then reverse-
    /// geocodes one representative coordinate per cluster to get a city name.
    /// Results are cached to disk so subsequent launches skip the network calls.
    private func buildPlacesCache() async {
        let snapshot = queue.sync { _index }

        // Collect entries that have location data.
        let locEntries = snapshot.values.filter {
            $0.hasLocation && $0.latitude != nil && $0.longitude != nil
            && $0.mediaType == PHAssetMediaType.image.rawValue && !$0.isHidden
        }
        guard !locEntries.isEmpty else {
            queue.sync {
                _cachedPlaces = []
                _placeToAssetIDs = [:]
            }
#if DEBUG
            print("📇 PhotoIndexService: no location entries – places cache empty.")
#endif
            return
        }

        // Round coordinates to 1 decimal place (~11 km clusters).
        struct CoordKey: Hashable {
            let latBucket: Int
            let lngBucket: Int
            var cacheKey: String { "\(latBucket),\(lngBucket)" }
        }
        var clusters: [CoordKey: (lat: Double, lng: Double, assetIDs: [String])] = [:]
        for entry in locEntries {
            let lat = Double(entry.latitude!)
            let lng = Double(entry.longitude!)
            let key = CoordKey(latBucket: Int((lat * 10).rounded()), lngBucket: Int((lng * 10).rounded()))
            if clusters[key] == nil {
                clusters[key] = (lat: lat, lng: lng, assetIDs: [entry.assetId])
            } else {
                clusters[key]!.assetIDs.append(entry.assetId)
            }
        }

        // Load previously geocoded results from disk.
        var geocodeCache = loadGeocodeCache()
        var geocodeCacheDirty = false

        let uncachedClusters = clusters.filter { geocodeCache[$0.key.cacheKey] == nil }

#if DEBUG
        print("📇 PhotoIndexService: \(clusters.count) location clusters – \(clusters.count - uncachedClusters.count) cached, \(uncachedClusters.count) need geocoding.")
#endif

        // Only hit the network for clusters we haven't geocoded before.
        if !uncachedClusters.isEmpty {
            let geocoder = CLGeocoder()
            var succeeded = 0
            var failed = 0

            for (key, cluster) in uncachedClusters {
                let location = CLLocation(latitude: cluster.lat, longitude: cluster.lng)
                do {
                    let placemarks = try await geocoder.reverseGeocodeLocation(location)
                    if let placemark = placemarks.first {
                        if let city = placemark.locality, !city.isEmpty {
                            geocodeCache[key.cacheKey] = city
                            geocodeCacheDirty = true
                            succeeded += 1
                        } else {
                            // Store empty string so we don't retry clusters
                            // where Apple returns a placemark but no locality.
                            geocodeCache[key.cacheKey] = ""
                            geocodeCacheDirty = true
#if DEBUG
                            print("📇 PhotoIndexService: ⚠️ nil locality for cluster (\(cluster.lat), \(cluster.lng)) with \(cluster.assetIDs.count) photos. name=\(placemark.name ?? "nil"), subLocality=\(placemark.subLocality ?? "nil"), administrativeArea=\(placemark.administrativeArea ?? "nil")")
#endif
                        }
                    }
                } catch {
                    failed += 1
#if DEBUG
                    print("📇 PhotoIndexService: geocode failed for (\(cluster.lat), \(cluster.lng)): \(error.localizedDescription)")
#endif
                    // Do NOT cache failures — we'll retry next time.
                }

                // Apple rate-limits CLGeocoder; 1.5s between requests avoids throttling.
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
            }

#if DEBUG
            print("📇 PhotoIndexService: geocoded \(succeeded) new clusters, \(failed) failed (will retry next launch).")
#endif
        }

        // Persist updated geocode cache if anything changed.
        if geocodeCacheDirty {
            saveGeocodeCache(geocodeCache)
        }

        // Build the placeMap from the (now-populated) geocode cache.
        var placeMap: [String: Set<String>] = [:]
        for (key, cluster) in clusters {
            if let city = geocodeCache[key.cacheKey], !city.isEmpty {
                var existing = placeMap[city] ?? []
                for id in cluster.assetIDs { existing.insert(id) }
                placeMap[city] = existing
            }
        }

        // Only include places with at least 20 photos so the wheel
        // isn't cluttered with one-off locations.
        let minPhotosPerPlace = 20
        let filtered = placeMap.filter { $0.value.count >= minPhotosPerPlace }
        let sortedPlaces = filtered.keys.sorted()
        queue.sync {
            _cachedPlaces = sortedPlaces
            _placeToAssetIDs = filtered
        }

#if DEBUG
        let totalIndexed = snapshot.count
        let withLocation = locEntries.count
        print("📇 PhotoIndexService: \(withLocation)/\(totalIndexed) photos have location data (\(Int(Double(withLocation) / Double(max(totalIndexed, 1)) * 100))%).")
        print("📇 PhotoIndexService: ── All geocoded places (sorted by count) ──")
        for (place, ids) in placeMap.sorted(by: { $0.value.count > $1.value.count }) {
            let status = ids.count >= minPhotosPerPlace ? "✅" : "❌"
            print("   \(status) \(place): \(ids.count) photos")
        }
        print("📇 PhotoIndexService: places cache built – \(sortedPlaces.count) places (dropped \(placeMap.count - filtered.count) with fewer than \(minPhotosPerPlace) photos).")
#endif
    }

    // MARK: - Private – People Cache (Documented API)

    /// Known system smart album titles that should never appear as "People".
    /// These are Apple's built-in album names across English + common locales.
    private static let knownSystemAlbumTitles: Set<String> = [
        // English
        "Recents", "Favorites", "Recently Deleted", "Screenshots",
        "Selfies", "Portrait", "Panoramas", "Videos", "Slo-mo",
        "Time-lapse", "Bursts", "Hidden", "Recently Added",
        "Live Photos", "Animated", "Long Exposure", "RAW",
        "Cinematic", "All Photos", "Camera Roll", "Imports",
        "Depth Effect", "Unable to Upload", "Spatial",
        // Also match PHAssetCollectionSubtype named cases
        "Photo Booth",
        // French
        "Récents", "Favoris", "Photos", "Vidéos", "Captures d'écran",
        "Autoportraits", "Portraits", "Panoramas", "Ralenti",
        "Accéléré", "Rafales", "Masqué", "Ajouts récents",
        "Live Photos", "Animé", "Longue exposition", "Cinématique",
        // Spanish
        "Recientes", "Favoritos", "Capturas de pantalla",
        "Selfis", "Retrato", "Panorámicas", "Cámara lenta",
        "Time-lapse", "Ráfagas", "Oculto", "Añadidos recientemente",
        // German
        "Zuletzt", "Favoriten", "Bildschirmfotos", "Selfies",
        "Porträt", "Panoramafotos", "Slo-Mo", "Zeitraffer",
        "Serien", "Ausgeblendet", "Zuletzt hinzugefügt",
        // Portuguese
        "Recentes", "Favoritas", "Capturas de Ecrã",
        // Italian
        "Recenti", "Preferite", "Istantanee schermo",
    ]

    /// Scans for People albums using multiple strategies, filtering out
    /// all known system smart albums from the results.
    private func buildPeopleCache() {
        var peopleNames: [String] = []

        // Method 1: Try the conventional People smart-album subtypes.
        // Apple has used different raw values across iOS versions.
        let candidateSubtypes: [Int] = [54, 210, 211, 212]
        for rawValue in candidateSubtypes {
            guard let subtype = PHAssetCollectionSubtype(rawValue: rawValue) else { continue }
            let results = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: subtype,
                options: nil
            )
            results.enumerateObjects { collection, _, _ in
                guard let title = collection.localizedTitle, !title.isEmpty else { return }
                let assets = PHAsset.fetchAssets(in: collection, options: nil)
                if assets.count > 0 { peopleNames.append(title) }
            }
        }

        // Method 2: Scan smart albums of type .album (not .smartAlbum).
        // On modern iOS (17+), People/Faces albums are often stored as
        // regular albums with subtype .smartAlbumFaces (1000101) or
        // similar non-smartAlbum types.  We scan all .album collections
        // and filter out system names afterwards.
        if peopleNames.isEmpty {
            let albumResults = PHAssetCollection.fetchAssetCollections(
                with: .album,
                subtype: .any,
                options: nil
            )
            albumResults.enumerateObjects { collection, _, _ in
                guard let title = collection.localizedTitle, !title.isEmpty else { return }
                let assets = PHAsset.fetchAssets(in: collection, options: nil)
                if assets.count > 0 { peopleNames.append(title) }
            }
        }

        // Method 3: Fallback — scan ALL smart albums.
        if peopleNames.isEmpty {
            let allSmartAlbums = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: .any,
                options: nil
            )
            allSmartAlbums.enumerateObjects { collection, _, _ in
                guard let title = collection.localizedTitle, !title.isEmpty else { return }
                let assets = PHAsset.fetchAssets(in: collection, options: nil)
                if assets.count > 0 { peopleNames.append(title) }
            }
        }

        // Filter out ALL known system album names regardless of which
        // method found them.  What remains should be actual people names.
        let filtered = peopleNames.filter { !Self.knownSystemAlbumTitles.contains($0) }
        let sorted = Array(Set(filtered)).sorted()

        queue.sync {
            _cachedPeople = sorted
        }

#if DEBUG
        print("📇 PhotoIndexService: people cache built – \(sorted.count) people from \(peopleNames.count) candidates (filtered \(peopleNames.count - filtered.count) system albums).")
#endif
    }

    /// Find a People album by scanning smart albums, regular albums, and
    /// all smart album subtypes for a matching title.
    private func findPeopleAlbumDocumented(named title: String) -> PHAssetCollection? {
        // Try known People smart-album subtypes first.
        let candidateSubtypes: [Int] = [54, 210, 211, 212]
        for rawValue in candidateSubtypes {
            guard let subtype = PHAssetCollectionSubtype(rawValue: rawValue) else { continue }
            let results = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: subtype,
                options: nil
            )
            var found: PHAssetCollection?
            results.enumerateObjects { collection, _, stop in
                if collection.localizedTitle == title {
                    found = collection
                    stop.pointee = true
                }
            }
            if let found { return found }
        }

        // Try regular albums (People albums on modern iOS).
        let albums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: nil
        )
        var albumMatch: PHAssetCollection?
        albums.enumerateObjects { collection, _, stop in
            if collection.localizedTitle == title {
                albumMatch = collection
                stop.pointee = true
            }
        }
        if let albumMatch { return albumMatch }

        // Fallback: scan all smart albums.
        let all = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .any,
            options: nil
        )
        var fallback: PHAssetCollection?
        all.enumerateObjects { collection, _, stop in
            if collection.localizedTitle == title {
                fallback = collection
                stop.pointee = true
            }
        }
        return fallback
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
