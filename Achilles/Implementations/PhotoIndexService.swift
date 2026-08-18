// PhotoIndexService.swift
//
// The on-device media index. It records visible photos and videos for Places,
// pre-scores images for collage selection, persists the result, and keeps it
// incrementally up-to-date via PHPhotoLibraryChangeObserver. A full rebuild is
// reserved for first use or recovery; normal launches restore immediately and
// reconcile in background.
//
// Architecture at a glance
// ─────────────────────────
//   IndexEntry          – the ~26-byte scored snapshot of one PHAsset.
//   PhotoIndexService   – owns the in-memory index, persistence, change
//                          observation, and all public queries.
//
// Persistence
//   Each IndexEntry is stored as an independent SQLite row in Application
//   Support. Legacy JSON snapshots are migrated once, preserving existing
//   users' completed indexes without making the globe rediscover old photos.
//
// Scoring
//   Delegates to the same logic used by FeaturedSelectorService.  The
//   score is cached in IndexEntry so queries never re-score.
//
// Threading
//   - buildIndex runs on a detached background task.
//   - All writes to the in-memory dictionary are serialised through
//     a single background serial queue.
//   - Query methods (topItems, available*) read a snapshot of the
//     dictionary on the caller's thread — safe because Swift Dictionary
//     is a value type and the snapshot is taken under the serial queue.

import Foundation
import Photos
import CoreLocation
import UIKit

/// A country or territory represented by at least one geotagged memory.
/// `coordinate` is the average of the indexed media coordinates and is used
/// to place a tappable marker even for very small territories.
struct CountryPhotoSummary: Identifiable, Equatable {
    let code: String
    let name: String
    let photoCount: Int
    let coordinate: CLLocationCoordinate2D

    var id: String { code }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.code == rhs.code && lhs.photoCount == rhs.photoCount
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

private struct GeocodeCacheEntry: Codable {
    let city: String
    let countryCode: String?
}


// MARK: - Persistence Wrapper

/// Legacy JSON envelope retained only for migration into PhotoIndexStore.
private struct IndexPersistencePayload: Codable {
    let version: Int
    let entries: [String: IndexEntry]
}

/// A cheap identifier-only diff used at launch. A changed library no longer
/// invalidates the complete index: only additions are scored/classified and
/// removals are deleted from the saved snapshot.
struct PhotoIndexReconciliationPlan: Equatable {
    let addedAssetIDs: Set<String>
    let removedAssetIDs: Set<String>
    let updatedAssetIDs: Set<String>

    static func make(
        persistedAssetIDs: Set<String>,
        currentAssetIDs: Set<String>,
        updatedAssetIDs: Set<String> = []
    ) -> Self {
        Self(
            addedAssetIDs: currentAssetIDs.subtracting(persistedAssetIDs),
            removedAssetIDs: persistedAssetIDs.subtracting(currentAssetIDs),
            updatedAssetIDs: updatedAssetIDs.intersection(currentAssetIDs)
        )
    }

    var hasChanges: Bool {
        !addedAssetIDs.isEmpty || !removedAssetIDs.isEmpty || !updatedAssetIDs.isEmpty
    }
}

/// Removes entries which can never be republished from a durable snapshot.
/// The live hidden-ID set closes the privacy gap where media was hidden while
/// Throwbaks was not running, without enumerating every visible photo first.
struct PhotoIndexRestorePlan {
    let entries: [String: IndexEntry]
    let removedAssetIDs: Set<String>

    static func make(
        persistedEntries: [String: IndexEntry],
        liveHiddenAssetIDs: Set<String>
    ) -> Self {
        let entries = persistedEntries.filter { assetID, entry in
            (entry.mediaType == PHAssetMediaType.image.rawValue
                || entry.mediaType == PHAssetMediaType.video.rawValue)
                && !entry.isHidden
                && !liveHiddenAssetIDs.contains(assetID)
        }
        return Self(
            entries: entries,
            removedAssetIDs: Set(persistedEntries.keys).subtracting(entries.keys)
        )
    }
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
    /// Persisted offline classification so reopening Places only groups IDs;
    /// it does not run every saved coordinate through country geometry again.
    var countryCode: String?
    /// PhotoKit metadata fingerprint. Location/date/edit changes preserve the
    /// local identifier but advance this value, allowing launch reconciliation
    /// to update only the affected saved entry.
    let modificationTimestamp: TimeInterval?

    // Derived / cached
    let creationYear: Int         // Calendar year of creationDate
    let score: Int                // Pre-computed quality score
}


// MARK: - PhotoIndexService

class PhotoIndexService: NSObject, PhotoIndexServiceProtocol, PHPhotoLibraryChangeObserver, @unchecked Sendable {

    // MARK: - Constants

    private struct Constants {
        /// Version 3 adds a PhotoKit metadata fingerprint.
        static let persistenceVersion: Int = 3
        static let migratablePersistenceVersions: Set<Int> = [1, 2, 3]

        /// UserDefaults keys
        static let countryOverridesKey = "PhotoIndex.countryOverrides"

        /// Durable Application Support filenames.
        static let indexFileName = "photo_index.json"
        static let indexDatabaseFileName = "photo_index.sqlite3"
        static let geocodeCacheFileName = "geocode_cache.json"
        static let storageDirectoryName = "PhotoIndex"

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

    /// Keeps disk snapshots ordered so an older asynchronous write cannot
    /// overwrite a newer photo-library state.
    private let persistenceQueue = DispatchQueue(
        label: "com.throwbaks.PhotoIndexService.persistence",
        qos: .utility
    )

    /// Accessed only from `persistenceQueue`; SQLite provides transactional,
    /// row-level writes for small PhotoKit change sets.
    private lazy var indexStore = PhotoIndexStore(databaseURL: indexDatabaseFilePath)

    /// Explicit corrections for ambiguous border/coastal coordinates. These
    /// are deliberately separate from derived index rows so PhotoKit metadata
    /// refreshes and recovery rebuilds cannot erase a user's correction.
    private let countryOverridesLock = NSLock()
    private var countryOverrides: [String: String] = [:]

    /// The in-memory index.  Only mutated on `queue`.
    private var _index: [String: IndexEntry] = [:]

    /// Invalidates cache work that started from an older index snapshot.
    private var _indexGeneration = 0

    /// Whether the index has completed at least one build.
    private var _isReady = false

    /// Guard against concurrent builds.
    private var _isBuildingIndex = false

    /// Serializes cold-start requests from startup prefetch and Places.
    private var _isBootstrappingIndex = false
    private var _bootstrapWaiters: [CheckedContinuation<Void, Never>] = []

    /// A restored snapshot is usable immediately, before this launch's cheap
    /// photo-ID reconciliation has completed.
    private var _hasReconciledCurrentLibrary = false
    private var _isReconciling = false
    private var _reconciliationRequestedWhileRunning = false

    /// Foreground notifications fire on every resume, not just after a Photos
    /// permission change. Tracking the last value avoids a needless full-library
    /// reconciliation each time the user returns to the app.
    private var _lastAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    /// The Photos fetch result from before the next library change. PhotoKit
    /// requires this exact object to calculate incremental change details.
    private var _assetFetchResult: PHFetchResult<PHAsset>?

    /// Cached place names derived from reverse-geocoding index coordinates.
    /// Populated during index build, BEFORE _isReady is set.
    private var _cachedPlaces: [String] = []

    /// Mapping from place name → set of asset IDs at that location.
    /// Used by topItems(forPlace:) to find photos at a given place.
    private var _placeToAssetIDs: [String: Set<String>] = [:]

    /// ISO 3166-1/Apple region code → geotagged asset IDs. Unlike the collage
    /// place cache this intentionally has no minimum-photo threshold.
    private var _countryToAssetIDs: [String: Set<String>] = [:]

    /// A representative coordinate for each visited country/territory.
    private var _countryCoordinates: [String: CLLocationCoordinate2D] = [:]

    /// Cached people names derived from the Photos People album.
    private var _cachedPeople: [String] = []

    /// Notification posted (on main thread) when the index finishes building
    /// and place/people caches are populated.  The ViewModel observes this
    /// to update its @Published properties.
    static let indexDidFinishBuilding = Notification.Name("PhotoIndexService.indexDidFinishBuilding")

    // MARK: - Protocol conformance – computed

    private var hasPhotoLibraryAccess: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    var isIndexReady: Bool {
        hasPhotoLibraryAccess && queue.sync { _isReady }
    }

    // MARK: - Singleton

    static let shared = PhotoIndexService()

    // MARK: - Initialisation

    private override init() {
        super.init()
        countryOverrides = UserDefaults.standard.dictionary(
            forKey: Constants.countryOverridesKey
        ) as? [String: String] ?? [:]
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
        guard hasPhotoLibraryAccess else {
            invalidatePublishedIndexForUnavailableAuthorization()
            return
        }

        let bootstrapOwnership = queue.sync { () -> Bool? in
            if _isReady { return nil }
            guard !_isBootstrappingIndex else { return false }
            _isBootstrappingIndex = true
            return true
        }

        if bootstrapOwnership == false {
            await waitForIndexBootstrap()
            if queue.sync(execute: { _isReady }) {
                await reconcileCurrentPhotoLibrary()
            }
            return
        }

        if bootstrapOwnership == true {
            defer { finishIndexBootstrap() }

            // Publish the last durable snapshot before comparing PhotoKit IDs.
            if await restorePersistedIndex() {
#if DEBUG
                print("📇 PhotoIndexService: restored durable index; reconciliation continuing in background.")
#endif
                Task(priority: .utility) { [weak self] in
                    await self?.reconcileCurrentPhotoLibrary()
                }
                return
            }

            // Cold start – build from scratch.
#if DEBUG
            print("📇 PhotoIndexService: no valid persisted index found, performing full build.")
#endif
            await performFullBuild()
            return
        }

        await reconcileCurrentPhotoLibrary()
    }

    private func waitForIndexBootstrap() async {
        await withCheckedContinuation { continuation in
            let shouldResumeImmediately = queue.sync { () -> Bool in
                guard _isBootstrappingIndex else { return true }
                _bootstrapWaiters.append(continuation)
                return false
            }
            if shouldResumeImmediately { continuation.resume() }
        }
    }

    private func finishIndexBootstrap() {
        let waiters = queue.sync { () -> [CheckedContinuation<Void, Never>] in
            _isBootstrappingIndex = false
            let waiters = _bootstrapWaiters
            _bootstrapWaiters.removeAll()
            return waiters
        }
        waiters.forEach { $0.resume() }
    }

    /// Waits for already-queued row-level writes and checkpoints SQLite's WAL.
    /// No snapshot rewrite is needed: every accepted PhotoKit delta is queued at
    /// the moment the in-memory index changes.
    func flushPendingWrites() async {
        await withCheckedContinuation { continuation in
            persistenceQueue.async {
                if FileManager.default.fileExists(atPath: self.indexDatabaseFilePath.path) {
                    do {
                        try self.indexStore.checkpoint()
                    } catch {
#if DEBUG
                        print("❌ PhotoIndexService: WAL checkpoint failed – \(error.localizedDescription)")
#endif
                    }
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Queries  (PhotoIndexServiceProtocol)

    func topItems(forYear year: Int, limit: Int = MemoryCollage.maxPhotos) -> [MediaItem] {
        guard hasPhotoLibraryAccess else { return [] }
        let snapshot = queue.sync { _index }
        let matched = snapshot.values
            .filter { $0.creationYear == year && $0.mediaType == PHAssetMediaType.image.rawValue && !$0.isHidden }
            .sorted { $0.score > $1.score }
            .prefix(limit)

        return resolveMediaItems(from: Array(matched))
    }

    func topItems(forPlace place: String, limit: Int = MemoryCollage.maxPhotos) -> [MediaItem] {
        guard hasPhotoLibraryAccess else { return [] }
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
        guard hasPhotoLibraryAccess else { return [] }
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
        guard hasPhotoLibraryAccess else { return [] }
        let snapshot = queue.sync { _index }
        let years = Set(
            snapshot.values
                .filter { $0.mediaType == PHAssetMediaType.image.rawValue && !$0.isHidden }
                .map { $0.creationYear }
        )
        return years.sorted(by: >)   // Most recent first
    }

    func availablePlaces() -> [String] {
        guard hasPhotoLibraryAccess else { return [] }
        return queue.sync { _cachedPlaces }
    }

    func availablePeople() -> [String] {
        guard hasPhotoLibraryAccess else { return [] }
        return queue.sync { _cachedPeople }
    }

    /// Every visited country/territory. Counts include visible geotagged photos
    /// and videos; hidden assets never enter this index.
    func countryPhotoSummaries(locale: Locale = .current) -> [CountryPhotoSummary] {
        guard hasPhotoLibraryAccess else { return [] }
        let snapshot = queue.sync { (_countryToAssetIDs, _countryCoordinates) }
        return snapshot.0.compactMap { code, ids in
            guard let coordinate = snapshot.1[code] else { return nil }
            let name = locale.localizedString(forRegionCode: code) ?? code
            return CountryPhotoSummary(
                code: code,
                name: name,
                photoCount: ids.count,
                coordinate: coordinate
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// All visible geotagged photos and videos for a country/territory.
    func items(forCountryCode countryCode: String) -> [MediaItem] {
        guard hasPhotoLibraryAccess else { return [] }
        let normalizedCode = countryCode.uppercased()
        let (snapshot, assetIDs) = queue.sync {
            (_index, _countryToAssetIDs[normalizedCode] ?? [])
        }
        let entries = assetIDs.compactMap { snapshot[$0] }
            .filter {
                $0.hasLocation && Self.isIndexedMediaType($0.mediaType) && !$0.isHidden
            }
            .sorted {
                if $0.creationYear != $1.creationYear { return $0.creationYear > $1.creationYear }
                return $0.score > $1.score
            }
        return resolveMediaItems(from: entries).sorted {
            ($0.asset.creationDate ?? .distantPast) > ($1.asset.creationDate ?? .distantPast)
        }
    }

    func setCountryOverride(_ countryCode: String?, forAssetID assetID: String) async {
        let normalizedCode = countryCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalizedCode == nil || normalizedCode?.count == 2 else { return }

        saveCountryOverride(normalizedCode, for: assetID)

        let updatedEntry = queue.sync { () -> IndexEntry? in
            guard var entry = _index[assetID],
                  entry.hasLocation,
                  let latitude = entry.latitude,
                  let longitude = entry.longitude else { return nil }
            entry.countryCode = normalizedCode ?? CountryBoundaryDataset.shared.countryCode(
                latitude: Double(latitude),
                longitude: Double(longitude)
            )
            _index[assetID] = entry
            _indexGeneration += 1
            return entry
        }
        guard let updatedEntry else { return }
        await persistIndexChangesDurably(upserts: [updatedEntry], removedAssetIDs: [])
        await buildPlacesCache(enrichCities: false)
    }

    // MARK: - PHPhotoLibraryChangeObserver

    func photoLibraryDidChange(_ changeInfo: PHChange) {
        guard hasPhotoLibraryAccess else {
            invalidatePublishedIndexForUnavailableAuthorization()
            return
        }
#if DEBUG
        print("📇 PhotoIndexService: PHPhotoLibrary change detected, performing incremental update.")
#endif
        // Run the incremental update on our serial queue so it doesn't race
        // with a concurrent full build.
        queue.async { [weak self] in
            self?.applyIncrementalUpdate(changeInfo)
        }
    }

    /// Called on foreground transitions because Photos permission can change
    /// while the app is in Settings. Cached results are hidden immediately if
    /// access is gone; restored/re-authorized libraries reconcile normally.
    func photoLibraryAuthorizationDidChange() {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let statusChanged = queue.sync { () -> Bool in
            let changed = _lastAuthorizationStatus != currentStatus
            _lastAuthorizationStatus = currentStatus
            return changed
        }

        guard currentStatus == .authorized || currentStatus == .limited else {
            invalidatePublishedIndexForUnavailableAuthorization()
            return
        }

        let needsMissingBaselineRecovery = queue.sync {
            _isReady && _assetFetchResult == nil && !_isReconciling
        }
        guard statusChanged || needsMissingBaselineRecovery else { return }

        queue.sync { _hasReconciledCurrentLibrary = false }
        Task(priority: .userInitiated) { [weak self] in
            await self?.buildIndex()
        }
    }

    private func invalidatePublishedIndexForUnavailableAuthorization() {
        let didChange = queue.sync { clearPublishedIndexLocked() }
        notifyIndexInvalidatedIfNeeded(didChange)
    }

    /// Must be called on `queue`.
    private func clearPublishedIndexLocked() -> Bool {
        let hadPublishedData = _isReady || !_countryToAssetIDs.isEmpty || !_cachedPlaces.isEmpty
        _index = [:]
        _indexGeneration += 1
        _assetFetchResult = nil
        _cachedPlaces = []
        _placeToAssetIDs = [:]
        _countryToAssetIDs = [:]
        _countryCoordinates = [:]
        _cachedPeople = []
        _isReady = false
        _isBuildingIndex = false
        _hasReconciledCurrentLibrary = false
        _isReconciling = false
        _reconciliationRequestedWhileRunning = false
        return hadPublishedData
    }

    private func notifyIndexInvalidatedIfNeeded(_ didChange: Bool) {
        guard didChange else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.indexDidFinishBuilding, object: nil)
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

        // Fetch visible photos and videos. PHAsset.fetchAssets is synchronous but
        // fast (it's a SQLite query against Apple's index).
        let options = Self.indexedMediaFetchOptions(isHidden: false)

        let fetchResult = PHAsset.fetchAssets(with: options)
#if DEBUG
        print("📇 PhotoIndexService: fetched \(fetchResult.count) visible photo/video assets.")
#endif

        // Score every asset.  This is CPU-bound but each score is O(1) —
        // just reading a handful of properties and doing arithmetic.
        var newIndex = [String: IndexEntry]()
        newIndex.reserveCapacity(fetchResult.count)

        fetchResult.enumerateObjects { asset, _, _ in
            guard let entry = self.buildEntry(for: asset) else { return }
            newIndex[entry.assetId] = entry
        }

        guard hasPhotoLibraryAccess else {
            queue.sync { _isBuildingIndex = false }
            invalidatePublishedIndexForUnavailableAuthorization()
            return
        }

        // Swap in the new index (but DON'T mark ready yet — caches first).
        queue.sync {
            self._index = newIndex
            self._indexGeneration += 1
            self._assetFetchResult = fetchResult
        }

        // Build place & people caches BEFORE marking ready, so that any
        // reader that checks isIndexReady will see populated caches.
        await buildPlacesCache(enrichCities: false)
        buildPeopleCache()

        // A completed first build must be durable before the UI says it is
        // done. Otherwise force-quitting immediately after indexing can lose
        // the fire-and-forget write and repeat the entire scan next launch.
        await persistIndexDurably(snapshot: newIndex)

        guard hasPhotoLibraryAccess else {
            queue.sync { _isBuildingIndex = false }
            invalidatePublishedIndexForUnavailableAuthorization()
            return
        }

        // NOW mark ready and allow builds again.
        queue.sync {
            self._isReady = true
            self._isBuildingIndex = false
            self._hasReconciledCurrentLibrary = true
        }

        let durationMs = Int(Date().timeIntervalSince(spanStart) * 1000)
#if DEBUG
        print("📇 PhotoIndexService: ── full build DONE ── \(newIndex.count) entries in \(durationMs) ms")
#endif

        // Notify observers (ViewModel) that data is available.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.indexDidFinishBuilding, object: nil)
        }

        // Country counts are now ready. City labels are optional enrichment
        // and should never keep Places in its indexing state on a cold start.
        Task(priority: .utility) { [weak self] in
            await self?.buildPlacesCache()
        }

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

    /// Reconcile a restored snapshot with the current library without
    /// rescoring or reclassifying unchanged media. Enumerating identifiers is
    /// a fast PhotoKit metadata query; the heavier work scales with additions.
    private func reconcileCurrentPhotoLibrary() async {
        let shouldRun = queue.sync { () -> Bool in
            guard _isReady, !_hasReconciledCurrentLibrary, !_isReconciling else { return false }
            _isReconciling = true
            return true
        }
        guard shouldRun else { return }

        let authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard authorization == .authorized || authorization == .limited else {
            queue.sync { _isReconciling = false }
            return
        }

        let spanStart = Date()
        let options = Self.indexedMediaFetchOptions(isHidden: false)
        let fetchResult = PHAsset.fetchAssets(with: options)
        let (persistedIndex, baseGeneration) = queue.sync { (_index, _indexGeneration) }
        let persistedIDs = Set(persistedIndex.keys)
        var currentIDs = Set<String>()
        currentIDs.reserveCapacity(fetchResult.count)
        var addedAssets: [PHAsset] = []
        var updatedAssets: [PHAsset] = []
        var updatedIDs = Set<String>()

        fetchResult.enumerateObjects { asset, _, _ in
            let id = asset.localIdentifier
            currentIDs.insert(id)
            if !persistedIDs.contains(id) {
                addedAssets.append(asset)
            } else if persistedIndex[id]?.modificationTimestamp != Self.modificationTimestamp(for: asset) {
                updatedAssets.append(asset)
                updatedIDs.insert(id)
            }
        }

        let plan = PhotoIndexReconciliationPlan.make(
            persistedAssetIDs: persistedIDs,
            currentAssetIDs: currentIDs,
            updatedAssetIDs: updatedIDs
        )
        var reconciledIndex = persistedIndex
        var upsertedEntries: [IndexEntry] = []
        plan.removedAssetIDs.forEach { reconciledIndex.removeValue(forKey: $0) }
        for asset in addedAssets + updatedAssets {
            guard let entry = buildEntry(for: asset) else {
                reconciledIndex.removeValue(forKey: asset.localIdentifier)
                continue
            }
            reconciledIndex[entry.assetId] = entry
            upsertedEntries.append(entry)
        }

        guard hasPhotoLibraryAccess else {
            queue.sync { _isReconciling = false }
            invalidatePublishedIndexForUnavailableAuthorization()
            return
        }

        let didPublish = queue.sync { () -> Bool in
            guard _indexGeneration == baseGeneration,
                  !_reconciliationRequestedWhileRunning else {
                _hasReconciledCurrentLibrary = false
                _isReconciling = false
                _reconciliationRequestedWhileRunning = false
                return false
            }
            _assetFetchResult = fetchResult
            _hasReconciledCurrentLibrary = true
            _isReconciling = false
            guard plan.hasChanges else { return true }
            _index = reconciledIndex
            _indexGeneration += 1
            return true
        }

        // A PhotoKit notification or manual correction raced this pass. Never
        // overwrite the newer in-memory generation with an older snapshot;
        // simply retry against the latest state in the background.
        guard didPublish else {
            Task(priority: .utility) { [weak self] in
                await self?.reconcileCurrentPhotoLibrary()
            }
            return
        }

        guard plan.hasChanges else {
            buildPeopleCache()
            Task(priority: .utility) { [weak self] in
                await self?.buildPlacesCache()
            }
#if DEBUG
            print("📇 PhotoIndexService: launch reconciliation found no library changes.")
#endif
            return
        }

        await buildPlacesCache(enrichCities: false)
        buildPeopleCache()
        await persistIndexChangesDurably(
            upserts: upsertedEntries,
            removedAssetIDs: plan.removedAssetIDs
        )
        Task(priority: .utility) { [weak self] in
            await self?.buildPlacesCache()
        }

        let durationMs = Int(Date().timeIntervalSince(spanStart) * 1_000)
#if DEBUG
        print(
            "📇 PhotoIndexService: launch reconciliation +\(plan.addedAssetIDs.count) "
                + "-\(plan.removedAssetIDs.count) ~\(plan.updatedAssetIDs.count) in \(durationMs) ms."
        )
#endif
        TelemetryService.shared.recordSpan(
            name: "photoIndex.incrementalReconciliation",
            startTime: spanStart,
            durationMs: durationMs,
            attributes: [
                "added_count": plan.addedAssetIDs.count,
                "removed_count": plan.removedAssetIDs.count,
                "updated_count": plan.updatedAssetIDs.count
            ]
        )
    }

    /// Walks the PHChange tree looking for asset-level changes (adds,
    /// removes, updates) and patches only those entries.
    private func applyIncrementalUpdate(_ changeInfo: PHChange) {
        guard hasPhotoLibraryAccess else {
            notifyIndexInvalidatedIfNeeded(clearPublishedIndexLocked())
            return
        }
        guard let priorFetchResult = _assetFetchResult else {
#if DEBUG
            print("📇 PhotoIndexService: missing prior fetch result; scheduling reconciliation.")
#endif
            _hasReconciledCurrentLibrary = false
            if _isReconciling {
                _reconciliationRequestedWhileRunning = true
            } else {
                Task(priority: .utility) { [weak self] in
                    await self?.reconcileCurrentPhotoLibrary()
                }
            }
            return
        }

        guard let changes = changeInfo.changeDetails(for: priorFetchResult) else {
#if DEBUG
            print("📇 PhotoIndexService: no asset-level changes detected.")
#endif
            return
        }

        var added   = 0
        var removed = 0
        var updated = 0
        var removedIDs = Set<String>()
        var upsertedEntries: [IndexEntry] = []

        let afterResult = changes.fetchResultAfterChanges
        _assetFetchResult = afterResult

        // ── Removed ──
        if let removedIndexes = changes.removedIndexes, removedIndexes.count > 0 {
            // Removed assets no longer exist — we can't fetch them.
            // Walk the *before* result to collect their IDs.
            let beforeResult = changes.fetchResultBeforeChanges
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
                guard let entry = buildEntry(for: asset) else {
                    removedIDs.insert(asset.localIdentifier)
                    _index.removeValue(forKey: asset.localIdentifier)
                    return
                }
                _index[entry.assetId] = entry
                upsertedEntries.append(entry)
            }
            added = insertedIndexes.count
        }

        // ── Updated (e.g. edited, location changed) ──
        if let changedIndexes = changes.changedIndexes, changedIndexes.count > 0 {
            changedIndexes.forEach { idx in
                let asset = afterResult.object(at: idx)
                guard let entry = buildEntry(for: asset) else {
                    removedIDs.insert(asset.localIdentifier)
                    _index.removeValue(forKey: asset.localIdentifier)
                    return
                }
                _index[entry.assetId] = entry
                upsertedEntries.append(entry)
            }
            updated = changedIndexes.count
        }

        if added + removed + updated > 0 {
            _indexGeneration += 1
#if DEBUG
            print("📇 PhotoIndexService: incremental update — +\(added) -\(removed) ~\(updated)")
#endif
            // Persist only the touched rows. For a 100-photo import this is
            // 100 small writes in one transaction, independent of library size.
            persistIndexChanges(
                upserts: upsertedEntries,
                removedAssetIDs: removedIDs
            )
            Task(priority: .utility) { [weak self] in
                await self?.buildPlacesCache(enrichCities: false)
                await self?.buildPlacesCache()
            }
        }
    }

    // MARK: - Private – Scoring

    /// Build an IndexEntry for a single PHAsset using the same scoring
    /// logic as FeaturedSelectorService.
    private static func modificationTimestamp(for asset: PHAsset) -> TimeInterval? {
        asset.modificationDate?.timeIntervalSinceReferenceDate
    }

    /// Returns nil for anything that must never enter the index. These checks
    /// are deliberately repeated even though normal fetches use predicates;
    /// PhotoKit change batches can race with a hide/type transition.
    private func buildEntry(for asset: PHAsset) -> IndexEntry? {
        guard Self.isIndexedMediaType(asset.mediaType), !asset.isHidden else { return nil }
        let year = asset.creationDate.map { Calendar.current.component(.year, from: $0) } ?? 0

        let loc = asset.location
        let lat: Float? = loc.map { Float($0.coordinate.latitude) }
        let lon: Float? = loc.map { Float($0.coordinate.longitude) }
        let countryCode = loc.flatMap {
            countryOverride(for: asset.localIdentifier) ?? CountryBoundaryDataset.shared.countryCode(
                latitude: $0.coordinate.latitude,
                longitude: $0.coordinate.longitude
            )
        }

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
            countryCode:      countryCode,
            modificationTimestamp: Self.modificationTimestamp(for: asset),
            creationYear:     year,
            score:            calculateScore(for: asset)
        )
        return entry
    }

    private func countryOverride(for assetID: String) -> String? {
        countryOverridesLock.lock()
        defer { countryOverridesLock.unlock() }
        return countryOverrides[assetID]
    }

    private func saveCountryOverride(_ countryCode: String?, for assetID: String) {
        countryOverridesLock.lock()
        if let countryCode {
            countryOverrides[assetID] = countryCode
        } else {
            countryOverrides.removeValue(forKey: assetID)
        }
        let savedOverrides = countryOverrides
        countryOverridesLock.unlock()
        UserDefaults.standard.set(savedOverrides, forKey: Constants.countryOverridesKey)
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

    /// Re-creatable, but important, index data belongs in Application Support:
    /// iOS is allowed to evict Caches at any time. The directory is excluded
    /// from device backups because Photos remains the source of truth.
    private var durableStorageDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Constants.storageDirectoryName, isDirectory: true)
    }

    private var legacyCacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    private func prepareDurableStorageAndMigrateLegacyFiles() throws {
        let fileManager = FileManager.default
        let directory = durableStorageDirectory
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        // This index is derived from the user's photo library and should not
        // consume their iCloud/device-backup allowance.
        var excludedDirectory = directory
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? excludedDirectory.setResourceValues(resourceValues)

        for fileName in [Constants.indexFileName, Constants.geocodeCacheFileName] {
            let destination = directory.appendingPathComponent(fileName)
            guard !fileManager.fileExists(atPath: destination.path) else { continue }

            let legacyFile = legacyCacheDirectory.appendingPathComponent(fileName)
            guard fileManager.fileExists(atPath: legacyFile.path) else { continue }
            try fileManager.copyItem(at: legacyFile, to: destination)
#if DEBUG
            print("📇 PhotoIndexService: migrated \(fileName) to Application Support.")
#endif
        }
    }

    /// Path to the persisted geocode cache file.
    private var geocodeCacheFilePath: URL {
        durableStorageDirectory.appendingPathComponent(Constants.geocodeCacheFileName)
    }

    /// Load previously geocoded bucket→placemark mappings from disk. The
    /// legacy string-only cache is migrated, then refreshed to add region codes.
    /// Key format: "v3:latBucket,lngBucket" (e.g. "v3:407,-740").
    private func loadGeocodeCache() -> [String: GeocodeCacheEntry] {
        do {
            try prepareDurableStorageAndMigrateLegacyFiles()
        } catch {
#if DEBUG
            print("❌ PhotoIndexService: failed to prepare durable storage – \(error.localizedDescription)")
#endif
            return [:]
        }
        guard FileManager.default.fileExists(atPath: geocodeCacheFilePath.path) else { return [:] }
        do {
            let data = try Data(contentsOf: geocodeCacheFilePath)
            if let current = try? JSONDecoder().decode([String: GeocodeCacheEntry].self, from: data) {
                return current
            }
            let legacy = try JSONDecoder().decode([String: String].self, from: data)
            return legacy.mapValues { GeocodeCacheEntry(city: $0, countryCode: nil) }
        } catch {
#if DEBUG
            print("📇 PhotoIndexService: failed to load geocode cache – \(error.localizedDescription)")
#endif
            return [:]
        }
    }

    /// Persist geocoded bucket→city mappings to disk.
    private func saveGeocodeCache(_ cache: [String: GeocodeCacheEntry]) {
        persistenceQueue.async {
            do {
                try self.prepareDurableStorageAndMigrateLegacyFiles()
                let data = try JSONEncoder().encode(cache)
                try data.write(to: self.geocodeCacheFilePath, options: .atomic)
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

    /// Path to the persisted index file in durable Application Support.
    private var indexFilePath: URL {
        durableStorageDirectory.appendingPathComponent(Constants.indexFileName)
    }

    private var indexDatabaseFilePath: URL {
        durableStorageDirectory.appendingPathComponent(Constants.indexDatabaseFileName)
    }

    private func writeIndexSnapshot(_ snapshot: [String: IndexEntry]) throws {
        try prepareDurableStorageAndMigrateLegacyFiles()
        let visibleEntries = snapshot.filter { _, entry in
            !entry.isHidden && Self.isIndexedMediaType(entry.mediaType)
        }
        try indexStore.replaceAll(
            with: visibleEntries,
            schemaVersion: Constants.persistenceVersion
        )
#if DEBUG
        print("📇 PhotoIndexService: persisted \(visibleEntries.count) visible entries to disk.")
#endif
    }

    private func writeIndexChanges(
        upserts: [IndexEntry],
        removedAssetIDs: Set<String>
    ) throws {
        try prepareDurableStorageAndMigrateLegacyFiles()
        let visibleUpserts = upserts.filter {
            !$0.isHidden && Self.isIndexedMediaType($0.mediaType)
        }
        let rejectedIDs = Set(upserts.lazy.filter {
            $0.isHidden || !Self.isIndexedMediaType($0.mediaType)
        }.map(\.assetId))
        try indexStore.apply(
            upserts: visibleUpserts,
            removing: removedAssetIDs.union(rejectedIDs),
            schemaVersion: Constants.persistenceVersion
        )
#if DEBUG
        print(
            "📇 PhotoIndexService: persisted index delta "
                + "+/~\(visibleUpserts.count) -\(removedAssetIDs.count + rejectedIDs.count)."
        )
#endif
    }

    /// Non-blocking row-level persistence for normal PhotoKit changes.
    private func persistIndexChanges(
        upserts: [IndexEntry],
        removedAssetIDs: Set<String>
    ) {
        guard !upserts.isEmpty || !removedAssetIDs.isEmpty else { return }
        persistenceQueue.async {
            do {
                try self.writeIndexChanges(
                    upserts: upserts,
                    removedAssetIDs: removedAssetIDs
                )
            } catch {
#if DEBUG
                print("❌ PhotoIndexService: failed to persist index delta – \(error.localizedDescription)")
#endif
            }
        }
    }

    /// Awaited for first-build and launch-reconciliation completion so a user
    /// cannot force-quit during the small window before the snapshot is safe.
    private func persistIndexDurably(snapshot: [String: IndexEntry]) async {
        await withCheckedContinuation { continuation in
            persistenceQueue.async {
                do {
                    try self.writeIndexSnapshot(snapshot)
                } catch {
#if DEBUG
                    print("❌ PhotoIndexService: failed to persist index – \(error.localizedDescription)")
#endif
                }
                continuation.resume()
            }
        }
    }

    private func persistIndexChangesDurably(
        upserts: [IndexEntry],
        removedAssetIDs: Set<String>
    ) async {
        guard !upserts.isEmpty || !removedAssetIDs.isEmpty else { return }
        await withCheckedContinuation { continuation in
            persistenceQueue.async {
                do {
                    try self.writeIndexChanges(
                        upserts: upserts,
                        removedAssetIDs: removedAssetIDs
                    )
                } catch {
#if DEBUG
                    print("❌ PhotoIndexService: failed to persist index delta – \(error.localizedDescription)")
#endif
                }
                continuation.resume()
            }
        }
    }

    private struct RestoredLibraryReconciliation {
        let index: [String: IndexEntry]
        let fetchResult: PHFetchResult<PHAsset>
        let plan: PhotoIndexReconciliationPlan
    }

    /// Limited-library access can remove previously selected assets without a
    /// normal deletion. In that mode we validate membership before publishing;
    /// a full-access library uses the faster hidden-only privacy pass below.
    private func reconcileRestoredEntries(
        _ persistedIndex: [String: IndexEntry]
    ) -> RestoredLibraryReconciliation {
        let options = Self.indexedMediaFetchOptions(isHidden: false)
        let fetchResult = PHAsset.fetchAssets(with: options)
        let persistedIDs = Set(persistedIndex.keys)
        var currentIDs = Set<String>()
        currentIDs.reserveCapacity(fetchResult.count)
        var assetsToUpsert: [PHAsset] = []
        var updatedIDs = Set<String>()

        fetchResult.enumerateObjects { asset, _, _ in
            let id = asset.localIdentifier
            currentIDs.insert(id)
            guard let persisted = persistedIndex[id] else {
                assetsToUpsert.append(asset)
                return
            }
            if persisted.modificationTimestamp != Self.modificationTimestamp(for: asset) {
                assetsToUpsert.append(asset)
                updatedIDs.insert(id)
            }
        }

        let plan = PhotoIndexReconciliationPlan.make(
            persistedAssetIDs: persistedIDs,
            currentAssetIDs: currentIDs,
            updatedAssetIDs: updatedIDs
        )
        var index = persistedIndex
        plan.removedAssetIDs.forEach { index.removeValue(forKey: $0) }
        for asset in assetsToUpsert {
            if let entry = buildEntry(for: asset) {
                index[entry.assetId] = entry
            } else {
                index.removeValue(forKey: asset.localIdentifier)
            }
        }
        return RestoredLibraryReconciliation(index: index, fetchResult: fetchResult, plan: plan)
    }

    /// Fetches only hidden photo/video identifiers. PhotoKit evaluates this predicate
    /// in its own indexed database, so work scales with the usually-small hidden
    /// result instead of requiring all visible assets to be materialized first.
    private func currentHiddenMediaAssetIDs() -> Set<String> {
        let options = Self.indexedMediaFetchOptions(isHidden: true)
        let fetchResult = PHAsset.fetchAssets(with: options)
        var identifiers = Set<String>()
        identifiers.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in
            identifiers.insert(asset.localIdentifier)
        }
        return identifiers
    }

    /// Restores and publishes the previous snapshot after a hidden-only privacy
    /// check. The O(library size) identifier/fingerprint reconciliation happens
    /// after readiness, so a large library never holds the globe loading UI.
    @discardableResult
    private func restorePersistedIndex() async -> Bool {
        let restoreStart = Date()
        let restored: (entries: [String: IndexEntry], sourceVersion: Int)? = await withCheckedContinuation { continuation in
            persistenceQueue.async {
                do {
                    try self.prepareDurableStorageAndMigrateLegacyFiles()
                    let fileManager = FileManager.default

                    if fileManager.fileExists(atPath: self.indexDatabaseFilePath.path) {
                        let entries = try self.indexStore.loadEntries()
                        continuation.resume(
                            returning: (entries, Constants.persistenceVersion)
                        )
                        return
                    }

                    // One-time migration for builds that stored one large JSON
                    // snapshot. The source file remains as a recovery fallback;
                    // all subsequent writes use the row-level database.
                    guard fileManager.fileExists(atPath: self.indexFilePath.path) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let data = try Data(contentsOf: self.indexFilePath)
                    let payload = try JSONDecoder().decode(IndexPersistencePayload.self, from: data)
                    guard Constants.migratablePersistenceVersions.contains(payload.version) else {
#if DEBUG
                        print(
                            "📇 PhotoIndexService: unsupported persisted index version "
                                + "\(payload.version); full rebuild required."
                        )
#endif
                        continuation.resume(returning: nil)
                        return
                    }

                    var entries = payload.entries
                    if payload.version == 1 {
                        for (assetID, var entry) in entries {
                            guard let latitude = entry.latitude,
                                  let longitude = entry.longitude else { continue }
                            entry.countryCode = CountryBoundaryDataset.shared.countryCode(
                                latitude: Double(latitude),
                                longitude: Double(longitude)
                            )
                            entries[assetID] = entry
                        }
#if DEBUG
                        print("📇 PhotoIndexService: migrated saved country assignments to index v2.")
#endif
                    }

                    try self.writeIndexSnapshot(entries)
#if DEBUG
                    print("📇 PhotoIndexService: migrated legacy JSON index to incremental storage.")
#endif

                    continuation.resume(returning: (entries, payload.version))
                } catch {
#if DEBUG
                    print("❌ PhotoIndexService: failed to restore persisted index – \(error.localizedDescription)")
#endif
                    continuation.resume(returning: nil)
                }
            }
        }

        guard let restored else {
#if DEBUG
            print("📇 PhotoIndexService: no usable persisted index found.")
#endif
            return false
        }

        guard hasPhotoLibraryAccess else {
            invalidatePublishedIndexForUnavailableAuthorization()
            return false
        }

        let authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let restorePlan = PhotoIndexRestorePlan.make(
            persistedEntries: restored.entries,
            liveHiddenAssetIDs: currentHiddenMediaAssetIDs()
        )

        // Limited access is the one launch mode where stale membership can
        // expose country counts for assets the user has deselected. Pay the
        // stricter full membership check before publishing in that mode.
        let limitedReconciliation: RestoredLibraryReconciliation? = authorization == .limited
            ? reconcileRestoredEntries(restorePlan.entries)
            : nil
        let publishedEntries = limitedReconciliation?.index ?? restorePlan.entries

        guard hasPhotoLibraryAccess else {
            invalidatePublishedIndexForUnavailableAuthorization()
            return false
        }

        queue.sync {
            _index = publishedEntries
            _indexGeneration += 1
            _assetFetchResult = limitedReconciliation?.fetchResult
            _hasReconciledCurrentLibrary = limitedReconciliation != nil
            _lastAuthorizationStatus = authorization
        }

        // Grouping persisted country codes is linear and local; no boundary
        // geometry, image decoding, or network request occurs on this path.
        await buildPlacesCache(enrichCities: false)
        queue.sync { _isReady = true }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.indexDidFinishBuilding, object: nil)
        }

        var removedAssetIDs = restorePlan.removedAssetIDs
        var upserts: [IndexEntry] = []
        if let limitedReconciliation {
            removedAssetIDs.formUnion(limitedReconciliation.plan.removedAssetIDs)
            let upsertIDs = limitedReconciliation.plan.addedAssetIDs
                .union(limitedReconciliation.plan.updatedAssetIDs)
            upserts = upsertIDs.compactMap { limitedReconciliation.index[$0] }
        }
        persistIndexChanges(upserts: upserts, removedAssetIDs: removedAssetIDs)

        if limitedReconciliation != nil {
            Task(priority: .utility) { [weak self] in
                self?.buildPeopleCache()
                await self?.buildPlacesCache()
            }
        }

#if DEBUG
        let durationMs = Int(Date().timeIntervalSince(restoreStart) * 1_000)
        print(
            "📇 PhotoIndexService: fast-restored \(publishedEntries.count) entries "
                + "from persisted index (v\(restored.sourceVersion)); "
                + "removed \(restorePlan.removedAssetIDs.count) hidden/invalid rows "
                + "in \(durationMs) ms."
        )
#endif
        TelemetryService.shared.recordSpan(
            name: "photoIndex.fastRestore",
            startTime: restoreStart,
            durationMs: Int(Date().timeIntervalSince(restoreStart) * 1_000),
            attributes: [
                "entry_count": publishedEntries.count,
                "removed_count": restorePlan.removedAssetIDs.count,
                "limited_access": authorization == .limited
            ]
        )
        return true
    }

    // MARK: - Private – Place Cache (Reverse Geocoding)

    /// Clusters index entries by rounded lat/lng (~10 km), then reverse-
    /// geocodes one representative coordinate per cluster to get a city name.
    /// Results are cached to disk so subsequent launches skip the network calls.
    private func buildPlacesCache(enrichCities: Bool = true) async {
        let (snapshot, indexGeneration) = queue.sync { (_index, _indexGeneration) }

        // Collect entries that have location data.
        let locEntries = snapshot.values.filter {
            $0.hasLocation && $0.latitude != nil && $0.longitude != nil
            && Self.isIndexedMediaType($0.mediaType) && !$0.isHidden
        }
        guard !locEntries.isEmpty else {
            let didPublish = queue.sync { () -> Bool in
                guard _indexGeneration == indexGeneration else { return false }
                _cachedPlaces = []
                _placeToAssetIDs = [:]
                _countryToAssetIDs = [:]
                _countryCoordinates = [:]
                return true
            }
#if DEBUG
            if didPublish {
                print("📇 PhotoIndexService: no location entries – places cache empty.")
            }
#endif
            if didPublish {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Self.indexDidFinishBuilding, object: nil)
                }
            }
            return
        }

        // Country assignments were computed once when each entry was added and
        // persisted with it. Reopening Places only groups those saved codes.
        var countryMap: [String: Set<String>] = [:]
        var countryCoordinateTotals: [String: GeographicCoordinateAccumulator] = [:]
        var locallyClassifiedIDs = Set<String>()
        for entry in locEntries {
            let latitude = Double(entry.latitude!)
            let longitude = Double(entry.longitude!)
            guard let code = entry.countryCode?.uppercased(), !code.isEmpty else { continue }
            countryMap[code, default: []].insert(entry.assetId)
            locallyClassifiedIDs.insert(entry.assetId)
            var accumulator = countryCoordinateTotals[code, default: GeographicCoordinateAccumulator()]
            accumulator.add(latitude: latitude, longitude: longitude)
            countryCoordinateTotals[code] = accumulator
        }

        func representativeCoordinates(
            from totals: [String: GeographicCoordinateAccumulator]
        ) -> [String: CLLocationCoordinate2D] {
            totals.reduce(into: [:]) { result, element in
                result[element.key] = element.value.coordinate
            }
        }

        // Publish the complete on-device country index immediately. City-name
        // enrichment below can involve many system geocoder calls and must not
        // hold the globe or its photo counts hostage.
        let didPublishCountryIndex = queue.sync { () -> Bool in
            guard _indexGeneration == indexGeneration else { return false }
            _countryToAssetIDs = countryMap
            _countryCoordinates = representativeCoordinates(from: countryCoordinateTotals)
            return true
        }
        guard didPublishCountryIndex else { return }
        guard enrichCities else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.indexDidFinishBuilding, object: nil)
            }
            return
        }

        // City names remain an optional geocoder enhancement. Coarser ~11 km
        // buckets keep request volume manageable; they no longer determine
        // whether a photo appears in a country.
        struct CoordKey: Hashable {
            let latBucket: Int
            let lngBucket: Int
            var cacheKey: String { "v3:\(latBucket),\(lngBucket)" }
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

        // Legacy cache entries have a city but no country code. Refresh those
        // once so Places can classify every geotagged photo.
        let uncachedClusters = clusters.filter {
            guard let cached = geocodeCache[$0.key.cacheKey] else { return true }
            return cached.countryCode == nil
        }

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
                        let city = placemark.locality ?? ""
                        let countryCode = placemark.isoCountryCode?.uppercased()
                        geocodeCache[key.cacheKey] = GeocodeCacheEntry(
                            city: city,
                            countryCode: countryCode
                        )
                        geocodeCacheDirty = true
                        if countryCode != nil { succeeded += 1 }
#if DEBUG
                        if city.isEmpty {
                            print("📇 PhotoIndexService: ⚠️ nil locality for cluster (\(cluster.lat), \(cluster.lng)) with \(cluster.assetIDs.count) photos. name=\(placemark.name ?? "nil"), subLocality=\(placemark.subLocality ?? "nil"), administrativeArea=\(placemark.administrativeArea ?? "nil")")
                        }
#endif
                    }
                } catch {
                    failed += 1
#if DEBUG
                    print("📇 PhotoIndexService: geocode failed for (\(cluster.lat), \(cluster.lng)): \(error.localizedDescription)")
#endif
                    // Do NOT cache failures — we'll retry next time.
                }

                // Requests are intentionally sequential. CLGeocoder already
                // applies service back-pressure, so an additional fixed delay
                // makes large libraries take minutes without improving accuracy.
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
        var fallbackCountryAssignments: [String: String] = [:]
        for (key, cluster) in clusters {
            guard let geocode = geocodeCache[key.cacheKey] else { continue }
            if !geocode.city.isEmpty {
                let city = geocode.city
                var existing = placeMap[city] ?? []
                // Collage place sources remain image-only even though country
                // exploration includes videos.
                for id in cluster.assetIDs {
                    guard let entry = snapshot[id],
                          entry.mediaType == PHAssetMediaType.image.rawValue else { continue }
                    existing.insert(id)
                }
                placeMap[city] = existing
            }
            if let code = geocode.countryCode, !code.isEmpty {
                // Geocoding is only a fallback for coordinates just outside
                // land geometry (for example a photo taken from a boat).
                let fallbackIDs = cluster.assetIDs.filter { !locallyClassifiedIDs.contains($0) }
                guard !fallbackIDs.isEmpty else { continue }
                let normalizedCode = code.uppercased()
                for id in fallbackIDs {
                    countryMap[normalizedCode, default: []].insert(id)
                    fallbackCountryAssignments[id] = normalizedCode
                }

                let weight = fallbackIDs.count
                var accumulator = countryCoordinateTotals[normalizedCode, default: GeographicCoordinateAccumulator()]
                accumulator.add(latitude: cluster.lat, longitude: cluster.lng, weight: weight)
                countryCoordinateTotals[normalizedCode] = accumulator
            }
        }

        // Only include places with at least 20 photos so the wheel
        // isn't cluttered with one-off locations.
        let minPhotosPerPlace = 20
        let filtered = placeMap.filter { $0.value.count >= minPhotosPerPlace }
        let sortedPlaces = filtered.keys.sorted()
        let countryCoordinates = representativeCoordinates(from: countryCoordinateTotals)
        let publication = queue.sync { () -> (didPublish: Bool, updatedEntries: [IndexEntry]) in
            guard _indexGeneration == indexGeneration else { return (false, []) }
            _cachedPlaces = sortedPlaces
            _placeToAssetIDs = filtered
            _countryToAssetIDs = countryMap
            _countryCoordinates = countryCoordinates
            var updatedEntries: [IndexEntry] = []
            for (assetID, countryCode) in fallbackCountryAssignments {
                guard _index[assetID]?.countryCode != countryCode else { continue }
                _index[assetID]?.countryCode = countryCode
                if let entry = _index[assetID] {
                    updatedEntries.append(entry)
                }
            }
            return (true, updatedEntries)
        }
        guard publication.didPublish else { return }
        persistIndexChanges(upserts: publication.updatedEntries, removedAssetIDs: [])
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.indexDidFinishBuilding, object: nil)
        }

#if DEBUG
        let totalIndexed = snapshot.count
        let withLocation = locEntries.count
        print("📇 PhotoIndexService: \(withLocation)/\(totalIndexed) memories have location data (\(Int(Double(withLocation) / Double(max(totalIndexed, 1)) * 100))%).")
        print("📇 PhotoIndexService: ── All geocoded places (sorted by count) ──")
        for (place, ids) in placeMap.sorted(by: { $0.value.count > $1.value.count }) {
            let status = ids.count >= minPhotosPerPlace ? "✅" : "❌"
            print("   \(status) \(place): \(ids.count) photos")
        }
        print("📇 PhotoIndexService: places cache built – \(sortedPlaces.count) places (dropped \(placeMap.count - filtered.count) with fewer than \(minPhotosPerPlace) photos).")
        print("📇 PhotoIndexService: country cache built – \(countryMap.count) visited countries/territories.")
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
                let assets = PHAsset.fetchAssets(
                    in: collection,
                    options: Self.visibleImageFetchOptions()
                )
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
                let assets = PHAsset.fetchAssets(
                    in: collection,
                    options: Self.visibleImageFetchOptions()
                )
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
                let assets = PHAsset.fetchAssets(
                    in: collection,
                    options: Self.visibleImageFetchOptions()
                )
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
        let assets = PHAsset.fetchAssets(
            in: collection,
            options: Self.visibleImageFetchOptions()
        )
        var ids = [String]()
        ids.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in
            ids.append(asset.localIdentifier)
        }
        return ids
    }

    private static func visibleImageFetchOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue),
            NSPredicate(format: "isHidden == NO")
        ])
        return options
    }

    private static func indexedMediaFetchOptions(isHidden: Bool) -> PHFetchOptions {
        let mediaPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue),
            NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        ])
        let options = PHFetchOptions()
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            mediaPredicate,
            NSPredicate(format: isHidden ? "isHidden == YES" : "isHidden == NO")
        ])
        return options
    }

    private static func isIndexedMediaType(_ mediaType: PHAssetMediaType) -> Bool {
        mediaType == .image || mediaType == .video
    }

    private static func isIndexedMediaType(_ rawValue: UInt8) -> Bool {
        rawValue == PHAssetMediaType.image.rawValue
            || rawValue == PHAssetMediaType.video.rawValue
    }

    // MARK: - Private – MediaItem resolution

    /// Given a set of IndexEntry values, fetch the live PHAssets and wrap
    /// them as MediaItems.  Entries whose asset no longer exists are silently
    /// dropped.
    private func resolveMediaItems(from entries: [IndexEntry]) -> [MediaItem] {
        guard hasPhotoLibraryAccess, !entries.isEmpty else { return [] }

        let ids = entries.map { $0.assetId }
        let options = Self.indexedMediaFetchOptions(isHidden: false)
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: options)

        // Build a lookup so we can return items in score order (not fetch order).
        var assetMap = [String: PHAsset]()
        assetMap.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in
            guard Self.isIndexedMediaType(asset.mediaType), !asset.isHidden else { return }
            assetMap[asset.localIdentifier] = asset
        }

        // Walk entries in their original (score-sorted) order.
        return entries.compactMap { entry in
            guard !entry.isHidden,
                  let asset = assetMap[entry.assetId],
                  !asset.isHidden else { return nil }
            return MediaItem(asset: asset)
        }
    }
}
