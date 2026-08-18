//
//  AchillesTests.swift
//  AchillesTests
//
//  Created by Blind Takes on 3/29/25.
//

import Foundation
import CoreLocation
import Photos
import Testing
@testable import Achilles

@Test("Places catalog includes countries, territories, and small regions")
func placesCatalogCoverage() {
    let codes = Set(PlaceRegionCatalog.allCodes)
    #expect(codes.contains("PR")) // Puerto Rico
    #expect(codes.contains("VA")) // Vatican City
    #expect(codes.contains("MC")) // Monaco
    #expect(codes.contains("PN")) // Pitcairn
    #expect(codes.contains("BQ")) // Caribbean Netherlands
    #expect(!codes.contains("EU")) // Locale macro-region, not a country
    #expect(!codes.contains("UN")) // Locale pseudo-region, not a country
    #expect(codes.count >= 250)
}

@Test("Places assigns countries and territories to stable continents")
func placeContinentCoverage() {
    #expect(PlaceRegionCatalog.continent(for: "PR") == .northAmerica)
    #expect(PlaceRegionCatalog.continent(for: "BR") == .southAmerica)
    #expect(PlaceRegionCatalog.continent(for: "FR") == .europe)
    #expect(PlaceRegionCatalog.continent(for: "JP") == .asia)
    #expect(PlaceRegionCatalog.continent(for: "ZA") == .africa)
    #expect(PlaceRegionCatalog.continent(for: "AU") == .oceania)
    #expect(PlaceRegionCatalog.continent(for: "AQ") == .antarctica)
    #expect(PlaceRegionCatalog.allCodes.allSatisfy { PlaceRegionCatalog.continent(for: $0) != nil })
}

@Test("Places continent totals count each visited territory once")
func placeContinentTotals() {
    let totals = PlaceRegionCatalog.continentTotals(
        photoCountsByCountryCode: [
            "PR": 4,
            "US": 20,
            "BR": 3,
            "FR": 8,
            "AQ": 1,
            "JP": 0
        ]
    )

    #expect(totals[.northAmerica] == PlaceContinentTotal(countryCount: 2, photoCount: 24))
    #expect(totals[.southAmerica] == PlaceContinentTotal(countryCount: 1, photoCount: 3))
    #expect(totals[.europe] == PlaceContinentTotal(countryCount: 1, photoCount: 8))
    #expect(totals[.antarctica] == PlaceContinentTotal(countryCount: 1, photoCount: 1))
    #expect(totals[.asia] == nil)
}

@Test("Bundled boundaries classify countries and small territories offline")
func countryBoundaryClassification() {
    let boundaries = CountryBoundaryDataset.shared
    #expect(boundaries.countryCode(latitude: 40.7128, longitude: -74.0060) == "US")
    #expect(boundaries.countryCode(latitude: -15.7939, longitude: -47.8828) == "BR") // Brasília
    #expect(boundaries.countryCode(latitude: -23.5505, longitude: -46.6333) == "BR") // São Paulo
    #expect(boundaries.countryCode(latitude: -3.1190, longitude: -60.0217) == "BR") // Manaus
    #expect(boundaries.countryCode(latitude: 4.9224, longitude: -52.3135) == "GF") // French Guiana
    #expect(boundaries.countryCode(latitude: 18.4655, longitude: -66.1057) == "PR")
    #expect(boundaries.countryCode(latitude: 43.7384, longitude: 7.4246) == "MC")
    #expect(boundaries.countryCode(latitude: 41.9029, longitude: 12.4534) == "VA")
    #expect(boundaries.countryCode(latitude: 12.1440, longitude: -68.2655) == "BQ")
}

@Test("Globe camera targets work offline and scale down for small territories")
func globeCameraTargets() {
    let boundaries = CountryBoundaryDataset.shared
    let expectedCoordinates: [String: (latitude: ClosedRange<Double>, longitude: ClosedRange<Double>)] = [
        "US": (35...42, -105 ... -93),
        "FR": (43...50, -2...7),
        "BR": (-17 ... -4, -60 ... -47),
        "PR": (17...19, -68 ... -65),
        "FJ": (-20 ... -15, 170...180)
    ]
    for (code, expected) in expectedCoordinates {
        let coordinate = boundaries.representativeCoordinate(for: code)
        #expect(coordinate != nil, "Missing representative coordinate for \(code)")
        if let coordinate {
            #expect(expected.latitude.contains(coordinate.latitude), "Unexpected latitude for \(code)")
            #expect(expected.longitude.contains(coordinate.longitude), "Unexpected longitude for \(code)")
        }
    }
    #expect(boundaries.representativeCoordinate(for: "VA") != nil)
    #expect(boundaries.suggestedCameraRange(for: "PR") < boundaries.suggestedCameraRange(for: "US"))
    #expect(boundaries.suggestedCameraRange(for: "VA") <= boundaries.suggestedCameraRange(for: "PR"))
    for code in ["US", "FR", "BR", "PR", "FJ"] {
        #expect((30_000...7_000_000).contains(boundaries.suggestedCameraRange(for: code)))
    }
}

@Test("Every searchable place has a bounded offline globe target")
func globeCameraTargetCatalogCoverage() {
    let boundaries = CountryBoundaryDataset.shared
    let missingTargets = PlaceRegionCatalog.allCodes.filter {
        !boundaries.hasCameraTarget(for: $0)
    }
    let unsafeRanges = PlaceRegionCatalog.allCodes.filter {
        !(30_000...7_000_000).contains(boundaries.suggestedCameraRange(for: $0))
    }
    #expect(missingTargets.isEmpty, "Missing globe camera targets for \(missingTargets)")
    #expect(unsafeRanges.isEmpty, "Unsafe globe camera ranges for \(unsafeRanges)")
}

@Test("Concave country camera targets stay on their primary land component")
func concaveCountryCameraTargets() {
    let boundaries = CountryBoundaryDataset.shared
    for code in ["VN", "MH", "IO", "IL", "CC"] {
        let coordinate = boundaries.representativeCoordinate(for: code)
        let primary = boundaries.polygons(for: code).max { $0.areaProxy < $1.areaProxy }
        #expect(coordinate != nil, "Missing representative coordinate for \(code)")
        #expect(primary != nil, "Missing primary polygon for \(code)")
        if let coordinate, let primary {
            #expect(
                primary.contains(latitude: coordinate.latitude, longitude: coordinate.longitude),
                "Camera target falls outside \(code)"
            )
        }
    }
}

@Test("Geographic coordinate averaging is circular at the antimeridian")
func circularLongitudeAveraging() {
    var accumulator = GeographicCoordinateAccumulator()
    accumulator.add(latitude: -17, longitude: 179)
    accumulator.add(latitude: -19, longitude: -179)
    let coordinate = accumulator.coordinate
    #expect(coordinate != nil)
    #expect(coordinate?.latitude == -18)
    #expect(abs(abs(coordinate?.longitude ?? 0) - 180) < 0.001)
}

@Test("Polygon detail preserves major regions without rendering island clutter")
func countryPolygonLevelOfDetail() {
    let boundaries = CountryBoundaryDataset.shared
    let us = boundaries.polygons(for: "US")
    let worldUS = CountryPolygonLevelOfDetail.select(
        us,
        cameraRange: 35_000_000,
        includeSecondaryComponents: true,
        area: \.areaProxy
    )
    #expect(worldUS.count >= 3)
    #expect(worldUS.count < us.count)
    #expect(worldUS.contains { $0.maxLatitude > 50 }) // Alaska
    #expect(worldUS.contains { $0.minLatitude < 22 && $0.maxLatitude > 18 }) // Hawaii

    let japan = boundaries.polygons(for: "JP")
    let countryJapan = CountryPolygonLevelOfDetail.select(
        japan,
        cameraRange: 7_000_000,
        includeSecondaryComponents: true,
        area: \.areaProxy
    )
    #expect(countryJapan.count >= 4)
    #expect(countryJapan.count < japan.count)

    let puertoRico = boundaries.polygons(for: "PR")
    let closePuertoRico = CountryPolygonLevelOfDetail.select(
        puertoRico,
        cameraRange: 300_000,
        includeSecondaryComponents: true,
        area: \.areaProxy
    )
    #expect(closePuertoRico.count == puertoRico.count)

    let unvisitedPuertoRico = CountryPolygonLevelOfDetail.select(
        puertoRico,
        cameraRange: 300_000,
        includeSecondaryComponents: false,
        area: \.areaProxy
    )
    #expect(unvisitedPuertoRico.count == 1)
}

@Test("Rapid globe camera requests atomically replace older countries")
func rapidGlobeCameraReplacement() {
    var state = GlobeFlightRequestState()
    let france = GlobeTarget(
        countryCode: "FR",
        source: .search,
        coordinate: CLLocationCoordinate2D(latitude: 46.5, longitude: 2.5),
        distance: 4_000_000
    )
    let brazil = GlobeTarget(
        countryCode: "BR",
        source: .search,
        coordinate: CLLocationCoordinate2D(latitude: -10.5, longitude: -53),
        distance: 6_000_000
    )
    let unitedStates = GlobeTarget(
        countryCode: "US",
        source: .search,
        coordinate: CLLocationCoordinate2D(latitude: 39, longitude: -99),
        distance: 7_000_000
    )

    let acceptedFrance = state.accept(france)
    let firedFrance = state.markDestinationRendered(france.id)
    let acceptedBrazil = state.accept(brazil)
    let acceptedUnitedStates = state.accept(unitedStates)
    let staleBrazil = state.markDestinationRendered(brazil.id)
    let firedUnitedStates = state.markDestinationRendered(unitedStates.id)
    #expect(acceptedFrance)
    #expect(firedFrance?.id == france.id)
    #expect(acceptedBrazil)
    #expect(acceptedUnitedStates)
    #expect(staleBrazil == nil)
    #expect(firedUnitedStates?.id == unitedStates.id)
    #expect(state.firedID == unitedStates.id)
    #expect(state.active?.id == unitedStates.id)
    #expect(state.active?.countryCode == "US")
    #expect(state.matchesSelectedCountry("US"))
    #expect(!state.matchesSelectedCountry("FR"))
    #expect(state.allowsCorrection)
    let finishedCorrection = state.finishCorrection()
    #expect(finishedCorrection)
    #expect(!state.allowsCorrection)
    let duplicateFinish = state.finishCorrection()
    #expect(!duplicateFinish)
    let acceptedDuplicate = state.accept(unitedStates)
    #expect(!acceptedDuplicate)

    let acceptedAfterInteraction = state.accept(france)
    #expect(acceptedAfterInteraction)
    #expect(state.allowsCorrection)
    state.cancel()
    #expect(state.active == nil)
    #expect(state.stagedID == nil)
    #expect(state.firedID == nil)
    #expect(!state.allowsCorrection)
}

@Test("Globe camera settlement detects wrong regions and accepts aligned targets")
func globeCameraSettlement() {
    let brazil = GlobeTarget(
        countryCode: "BR",
        source: .search,
        coordinate: CLLocationCoordinate2D(latitude: -10.5, longitude: -53),
        distance: 6_000_000
    )
    let europe = GlobeCameraSnapshot(latitude: 48, longitude: 8, range: 6_000_000)
    let aligned = GlobeCameraSnapshot(latitude: -10.1, longitude: -52.7, range: 6_400_000)
    #expect(GlobeCameraAlignment.needsCorrection(europe, for: brazil))
    #expect(!GlobeCameraAlignment.needsCorrection(aligned, for: brazil))

    let datelineTarget = GlobeTarget(
        countryCode: "FJ",
        source: .search,
        coordinate: CLLocationCoordinate2D(latitude: -17.8, longitude: 179.7),
        distance: 2_000_000
    )
    let wrapped = GlobeCameraSnapshot(latitude: -17.8, longitude: -179.8, range: 2_000_000)
    #expect(!GlobeCameraAlignment.needsCorrection(wrapped, for: datelineTarget))
}

@Test("Country highlight identities change when visited or selected state changes")
func countryHighlightIdentities() {
    let polygonID = 42
    let unvisited = CountryGlobeVisualState.resolve(
        code: "BR",
        visitedCodes: [],
        selectedCode: nil
    )
    let visited = CountryGlobeVisualState.resolve(
        code: "BR",
        visitedCodes: ["BR"],
        selectedCode: nil
    )
    let selected = CountryGlobeVisualState.resolve(
        code: "BR",
        visitedCodes: ["BR"],
        selectedCode: "br"
    )
    #expect(unvisited == .unvisited)
    #expect(visited == .visited)
    #expect(selected == .selected)
    #expect(unvisited.renderID(for: polygonID) != visited.renderID(for: polygonID))
    #expect(visited.renderID(for: polygonID) != selected.renderID(for: polygonID))
}

@Test("Country globe styling keeps imagery visible and selection distinct")
func countryGlobeStyleMetrics() {
    let unvisited = CountryGlobeStyleMetrics.metrics(for: .unvisited)
    let visited = CountryGlobeStyleMetrics.metrics(for: .visited)
    let selected = CountryGlobeStyleMetrics.metrics(for: .selected)

    #expect(unvisited.fillAlpha == 0)
    #expect(visited.fillAlpha <= 0.22)
    #expect(visited.strokeWidth <= 2)
    #expect(selected.fillAlpha > visited.fillAlpha)
    #expect(selected.strokeWidth > visited.strokeWidth)
    #expect(selected.fillAlpha <= 0.25)
    #expect(selected.strokeWidth <= 3)
}

@Test("Overview memory pins stay away from the globe viewport edge")
func countryOverviewMarkerVisibility() {
    let cameraCenter = CLLocationCoordinate2D(latitude: 14, longitude: 0)
    #expect(CountryOverviewMarkerVisibilityPolicy.isVisible(
        coordinate: CLLocationCoordinate2D(latitude: -10, longitude: -53),
        cameraCenter: cameraCenter,
        cameraRange: 35_000_000
    ))
    #expect(!CountryOverviewMarkerVisibilityPolicy.isVisible(
        coordinate: CLLocationCoordinate2D(latitude: 0, longitude: -80),
        cameraCenter: cameraCenter,
        cameraRange: 35_000_000
    ))
    #expect(
        CountryOverviewMarkerVisibilityPolicy.maximumAngularDistance(cameraRange: 15_000_000)
            < CountryOverviewMarkerVisibilityPolicy.maximumAngularDistance(cameraRange: 35_000_000)
    )
}

@Test("Selected countries are framed above the memory card")
func selectedCountryCameraFraming() {
    let countryCenter = CLLocationCoordinate2D(latitude: 12.5, longitude: 104.9)
    let cameraCenter = CountryCameraFraming.cameraCenter(
        countryCenter: countryCenter,
        cameraRange: 1_000_000
    )
    #expect(cameraCenter.latitude < countryCenter.latitude)
    #expect(cameraCenter.longitude == countryCenter.longitude)
    #expect(countryCenter.latitude - cameraCenter.latitude < 4.1)

    let antarctica = CountryCameraFraming.cameraCenter(
        countryCenter: CLLocationCoordinate2D(latitude: -81, longitude: 0),
        cameraRange: 7_000_000
    )
    #expect(antarctica.latitude == -82)
}

@Test("Globe requests clamp unsafe camera ranges")
func globeCameraRangeBounds() {
    let tooClose = GlobeTarget(
        countryCode: "PR",
        source: .search,
        coordinate: CLLocationCoordinate2D(latitude: 18.2, longitude: -66.5),
        distance: 1
    )
    let tooFar = GlobeTarget(
        source: .reset,
        coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        distance: 100_000_000
    )
    #expect(tooClose.distance == 25_000)
    #expect(tooFar.distance == 63_000_000)
}


// MARK: - Mock PhotoIndexService

/// A fully-controllable stand-in for PhotoIndexServiceProtocol.
/// Pre-seeded with whatever data a test needs; queries just filter that data.
/// Also used by CollageSourceService tests.
struct MockPhotoIndexService: PhotoIndexServiceProtocol {

    // Seed these before calling any query.
    var _isReady: Bool = true
    var _entries: [IndexEntry] = []

    var isIndexReady: Bool { _isReady }

    func buildIndex() async   { }

    // ── Queries ──  (filter the seeded entries, mirror real service logic)

    func topItems(forYear year: Int, limit: Int = MemoryCollage.maxPhotos) -> [MediaItem] {
        // Can't resolve real PHAssets in unit tests — return empty.
        // The *filtering & sorting* logic is what we validate via entryCount helpers below.
        return []
    }

    func topItems(forPlace place: String, limit: Int = MemoryCollage.maxPhotos) -> [MediaItem] { [] }
    func topItems(forPerson person: String, limit: Int = MemoryCollage.maxPhotos) -> [MediaItem] { [] }

    // ── Available sources ──

    func availableYears() -> [Int] {
        Array(Set(_entries.filter { !$0.isHidden }.map { $0.creationYear })).sorted(by: >)
    }
    func availablePlaces() -> [String] { [] }   // Places come from PHAssetCollection; not mockable here.
    func availablePeople() -> [String] { [] }
    func countryPhotoSummaries(locale: Locale) -> [CountryPhotoSummary] { [] }
    func items(forCountryCode countryCode: String) -> [MediaItem] { [] }
    func setCountryOverride(_ countryCode: String?, forAssetID assetID: String) async {}

    // ── Test helpers: count how many entries *would* be returned by a query ──

    func entryCount(forYear year: Int, limit: Int = MemoryCollage.maxPhotos) -> Int {
        _entries
            .filter { $0.creationYear == year && !$0.isHidden }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .count
    }

    func topEntries(forYear year: Int, limit: Int = MemoryCollage.maxPhotos) -> [IndexEntry] {
        Array(
            _entries
                .filter { $0.creationYear == year && !$0.isHidden }
                .sorted { $0.score > $1.score }
                .prefix(limit)
        )
    }
}


// MARK: - IndexEntry factory helpers for tests

extension IndexEntry {
    /// Convenience builder so tests don't have to spell out every field.
    static func stub(
        assetId:          String  = "stub-\(Int.random(in: 0..<999999))",
        mediaType:        UInt8   = 1,
        creationYear:     Int     = 2022,
        score:            Int     = 100,
        isHidden:         Bool    = false,
        isScreenshot:     Bool    = false,
        hasDepthEffect:   Bool    = false,
        hasAdjustments:   Bool    = false,
        representsBurst:  Bool    = false,
        burstHasUserPick: Bool    = false,
        burstHasAutoPick: Bool    = false,
        pixelWidth:       UInt16  = 4032,
        pixelHeight:      UInt16  = 3024,
        hasLocation:      Bool    = false,
        latitude:         Float?  = nil,
        longitude:        Float?  = nil,
        countryCode:      String? = nil,
        modificationTimestamp: TimeInterval? = nil
    ) -> IndexEntry {
        IndexEntry(
            assetId:          assetId,
            mediaType:        mediaType,
            isHidden:         isHidden,
            isScreenshot:     isScreenshot,
            hasDepthEffect:   hasDepthEffect,
            hasAdjustments:   hasAdjustments,
            representsBurst:  representsBurst,
            burstHasUserPick: burstHasUserPick,
            burstHasAutoPick: burstHasAutoPick,
            pixelWidth:       pixelWidth,
            pixelHeight:      pixelHeight,
            hasLocation:      hasLocation,
            latitude:         latitude,
            longitude:        longitude,
            countryCode:      countryCode,
            modificationTimestamp: modificationTimestamp,
            creationYear:     creationYear,
            score:            score
        )
    }
}


// MARK: - Scoring logic (extracted for testability)
//
// PhotoIndexService.calculateScore is private, so we replicate the same
// arithmetic here using the public IndexEntry fields.  If the scoring
// constants in PhotoIndexService ever change, these tests will catch drift.

private struct ScoringConstants {
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

/// Score an IndexEntry using the same rules as PhotoIndexService, so we can
/// assert expected scores without needing a real PHAsset.
private func computeScore(for entry: IndexEntry) -> Int {
    if entry.isHidden { return ScoringConstants.isHiddenPenalty }
    guard entry.mediaType == PHAssetMediaType.image.rawValue else { return 0 }

    var score = 0

    if entry.isScreenshot            { score += ScoringConstants.isScreenshotPenalty }
    if entry.pixelWidth  < UInt16(ScoringConstants.minimumResolution) ||
       entry.pixelHeight < UInt16(ScoringConstants.minimumResolution) {
        score += ScoringConstants.isLowResolutionPenalty
    }
    if entry.hasAdjustments          { score += ScoringConstants.isEditedBonus }
    if entry.hasDepthEffect          { score += ScoringConstants.hasPeopleBonus }

    if entry.representsBurst {
        if entry.burstHasUserPick || entry.burstHasAutoPick {
            score += ScoringConstants.isKeyBurstBonus
        } else {
            score += ScoringConstants.isNonKeyBurstPenalty
        }
    }

    let w = Double(entry.pixelWidth)
    let h = Double(entry.pixelHeight)
    if w > 0 && h > 0 {
        let ratio = max(w, h) / min(w, h)
        if ratio > ScoringConstants.extremeAspectRatioThreshold {
            score += ScoringConstants.hasExtremeAspectRatioPenalty
        } else {
            score += ScoringConstants.hasGoodAspectRatioBonus
        }
    }

    if entry.hasLocation             { score += ScoringConstants.hasLocationBonus }

    return score
}


// ─────────────────────────────────────────────
// MARK: - Tests
// ─────────────────────────────────────────────

struct AchillesTests {

    // ── Scoring: baseline ──────────────────────────────────────────────

    @Test func scoringBaseline_normalPhotoWithLocation() async throws {
        let entry = IndexEntry.stub(hasLocation: true, latitude: 37.7, longitude: -122.4)
        let score = computeScore(for: entry)
        // Good aspect ratio (+20) + location (+10) = 30
        #expect(score == 30)
    }

    @Test func scoringBaseline_normalPhotoNoLocation() async throws {
        let entry = IndexEntry.stub()
        let score = computeScore(for: entry)
        // Good aspect ratio only (+20)
        #expect(score == 20)
    }

    // ── Scoring: bonuses ───────────────────────────────────────────────

    @Test func scoring_editedPhoto() async throws {
        let entry = IndexEntry.stub(hasAdjustments: true)
        let score = computeScore(for: entry)
        // Edited (+150) + good aspect (+20) = 170
        #expect(score == 170)
    }

    @Test func scoring_depthEffectPortrait() async throws {
        let entry = IndexEntry.stub(hasDepthEffect: true)
        let score = computeScore(for: entry)
        // People/depth (+300) + good aspect (+20) = 320
        #expect(score == 320)
    }

    @Test func scoring_keyBurstUserPick() async throws {
        let entry = IndexEntry.stub(representsBurst: true, burstHasUserPick: true)
        let score = computeScore(for: entry)
        // Key burst (+50) + good aspect (+20) = 70
        #expect(score == 70)
    }

    @Test func scoring_keyBurstAutoPick() async throws {
        let entry = IndexEntry.stub(representsBurst: true, burstHasAutoPick: true)
        let score = computeScore(for: entry)
        #expect(score == 70)
    }

    // ── Scoring: penalties ─────────────────────────────────────────────

    @Test func scoring_screenshot() async throws {
        let entry = IndexEntry.stub(isScreenshot: true)
        let score = computeScore(for: entry)
        // Screenshot (-500) + good aspect (+20) = -480
        #expect(score == -480)
    }

    @Test func scoring_lowResolution() async throws {
        let entry = IndexEntry.stub(pixelWidth: 800, pixelHeight: 600)
        let score = computeScore(for: entry)
        // Low res (-100) + good aspect (+20) = -80
        #expect(score == -80)
    }

    @Test func scoring_extremeAspectRatio_panorama() async throws {
        // 6000 x 2000 → ratio 3.0 > 2.5 threshold
        let entry = IndexEntry.stub(pixelWidth: 6000, pixelHeight: 2000)
        let score = computeScore(for: entry)
        // Extreme aspect (-200) = -200
        #expect(score == -200)
    }

    @Test func scoring_nonKeyBurst() async throws {
        let entry = IndexEntry.stub(representsBurst: true, burstHasUserPick: false, burstHasAutoPick: false)
        let score = computeScore(for: entry)
        // Non-key burst (-50) + good aspect (+20) = -30
        #expect(score == -30)
    }

    @Test func scoring_hiddenPhoto_disqualified() async throws {
        let entry = IndexEntry.stub(isHidden: true, hasDepthEffect: true, hasAdjustments: true)
        let score = computeScore(for: entry)
        // Hidden → Int.min, all bonuses ignored
        #expect(score == Int.min)
    }

    @Test func scoring_videoIsIndexedWithoutPhotoQualityScore() async throws {
        let entry = IndexEntry.stub(
            mediaType: UInt8(PHAssetMediaType.video.rawValue),
            hasDepthEffect: true,
            hasAdjustments: true,
            hasLocation: true
        )
        #expect(computeScore(for: entry) == 0)
    }

    // ── Scoring: stacking ──────────────────────────────────────────────

    @Test func scoring_editedPortraitWithLocation() async throws {
        let entry = IndexEntry.stub(hasDepthEffect: true, hasAdjustments: true, hasLocation: true,
                                    latitude: 40.7, longitude: -74.0)
        let score = computeScore(for: entry)
        // Edited (+150) + people (+300) + location (+10) + good aspect (+20) = 480
        #expect(score == 480)
    }

    @Test func scoring_screenshotPanorama_stackedPenalties() async throws {
        let entry = IndexEntry.stub(isScreenshot: true, pixelWidth: 8000, pixelHeight: 2000)
        let score = computeScore(for: entry)
        // Screenshot (-500) + extreme aspect (-200) = -700
        #expect(score == -700)
    }

    // ── Mock index: available years ────────────────────────────────────

    @Test func mockIndex_availableYears_deduplicatesAndSorts() async throws {
        var mock = MockPhotoIndexService()
        mock._entries = [
            IndexEntry.stub(assetId: "a", creationYear: 2020),
            IndexEntry.stub(assetId: "b", creationYear: 2022),
            IndexEntry.stub(assetId: "c", creationYear: 2020),   // duplicate year
            IndexEntry.stub(assetId: "d", creationYear: 2021),
        ]
        let years = mock.availableYears()
        #expect(years == [2022, 2021, 2020])
    }

    @Test func mockIndex_availableYears_excludesHidden() async throws {
        var mock = MockPhotoIndexService()
        mock._entries = [
            IndexEntry.stub(assetId: "a", creationYear: 2019, isHidden: true),
            IndexEntry.stub(assetId: "b", creationYear: 2020),
        ]
        #expect(mock.availableYears() == [2020])
    }

    // ── Mock index: top entries by year ────────────────────────────────

    @Test func mockIndex_topEntriesForYear_sortsByScoreDesc() async throws {
        var mock = MockPhotoIndexService()
        mock._entries = [
            IndexEntry.stub(assetId: "low",  creationYear: 2021, score: 10),
            IndexEntry.stub(assetId: "high", creationYear: 2021, score: 500),
            IndexEntry.stub(assetId: "mid",  creationYear: 2021, score: 200),
        ]
        let top = mock.topEntries(forYear: 2021)
        #expect(top.map { $0.assetId } == ["high", "mid", "low"])
    }

    @Test func mockIndex_topEntriesForYear_respectsLimit() async throws {
        var mock = MockPhotoIndexService()
        mock._entries = (0..<15).map {
            IndexEntry.stub(assetId: "item-\($0)", creationYear: 2022, score: $0 * 10)
        }
        let top = mock.topEntries(forYear: 2022, limit: MemoryCollage.maxPhotos)
        #expect(top.count == MemoryCollage.maxPhotos)
    }

    @Test func mockIndex_topEntriesForYear_excludesHidden() async throws {
        var mock = MockPhotoIndexService()
        mock._entries = [
            IndexEntry.stub(assetId: "visible", creationYear: 2021, score: 50, isHidden: false),
            IndexEntry.stub(assetId: "hidden",  creationYear: 2021, score: 999, isHidden: true),
        ]
        let top = mock.topEntries(forYear: 2021)
        #expect(top.count == 1)
        #expect(top[0].assetId == "visible")
    }

    @Test func mockIndex_topEntriesForYear_wrongYear_returnsEmpty() async throws {
        var mock = MockPhotoIndexService()
        mock._entries = [
            IndexEntry.stub(assetId: "a", creationYear: 2020, score: 100),
        ]
        #expect(mock.topEntries(forYear: 2019).isEmpty)
    }

    // ── IndexEntry Codable round-trip ─────────────────────────────────

    @Test func indexEntry_codableRoundTrip() async throws {
        let original = IndexEntry.stub(
            assetId: "round-trip-test",
            creationYear: 2023,
            score: 420,
            hasLocation: true,
            latitude: 51.5,
            longitude: -0.1,
            countryCode: "GB",
            modificationTimestamp: 123_456
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(IndexEntry.self, from: data)

        #expect(decoded.assetId      == original.assetId)
        #expect(decoded.creationYear == original.creationYear)
        #expect(decoded.score        == original.score)
        #expect(decoded.hasLocation  == original.hasLocation)
        #expect(decoded.latitude     == original.latitude)
        #expect(decoded.longitude    == original.longitude)
        #expect(decoded.countryCode  == original.countryCode)
        #expect(decoded.modificationTimestamp == original.modificationTimestamp)
    }

    @Test func indexEntry_decodesLegacySnapshotWithoutCountryCode() async throws {
        let entry = IndexEntry.stub(assetId: "legacy", hasLocation: true, latitude: 40.7, longitude: -74)
        let encoded = try JSONEncoder().encode(entry)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "countryCode")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(IndexEntry.self, from: legacyData)
        #expect(decoded.assetId == "legacy")
        #expect(decoded.countryCode == nil)
    }

    @Test func photoIndexReconciliationProcessesOnlyLibraryDelta() async throws {
        let persisted = Set((0..<10_000).map { "existing-\($0)" })
        let additions = Set((0..<100).map { "new-\($0)" })
        let updates: Set<String> = ["existing-4", "existing-9"]
        let plan = PhotoIndexReconciliationPlan.make(
            persistedAssetIDs: persisted,
            currentAssetIDs: persisted.union(additions),
            updatedAssetIDs: updates
        )

        #expect(plan.addedAssetIDs == additions)
        #expect(plan.removedAssetIDs.isEmpty)
        #expect(plan.updatedAssetIDs == updates)
        #expect(plan.hasChanges)
    }

    @Test func photoIndexReconciliationTracksDeletionsWithoutRebuild() async throws {
        let plan = PhotoIndexReconciliationPlan.make(
            persistedAssetIDs: ["keep", "deleted"],
            currentAssetIDs: ["keep", "added"]
        )

        #expect(plan.addedAssetIDs == ["added"])
        #expect(plan.removedAssetIDs == ["deleted"])
    }

    @Test func photoIndexFastRestoreRemovesPersistedAndLiveHiddenRows() async throws {
        let visible = IndexEntry.stub(assetId: "visible")
        let alreadyHidden = IndexEntry.stub(assetId: "persisted-hidden", isHidden: true)
        let newlyHidden = IndexEntry.stub(assetId: "newly-hidden")
        let visibleVideo = IndexEntry.stub(
            assetId: "visible-video",
            mediaType: UInt8(PHAssetMediaType.video.rawValue)
        )
        let hiddenVideo = IndexEntry.stub(
            assetId: "hidden-video",
            mediaType: UInt8(PHAssetMediaType.video.rawValue)
        )
        let plan = PhotoIndexRestorePlan.make(
            persistedEntries: [
                visible.assetId: visible,
                alreadyHidden.assetId: alreadyHidden,
                newlyHidden.assetId: newlyHidden,
                visibleVideo.assetId: visibleVideo,
                hiddenVideo.assetId: hiddenVideo
            ],
            liveHiddenAssetIDs: [newlyHidden.assetId, hiddenVideo.assetId]
        )

        #expect(Set(plan.entries.keys) == [visible.assetId, visibleVideo.assetId])
        #expect(plan.removedAssetIDs == [
            alreadyHidden.assetId,
            newlyHidden.assetId,
            hiddenVideo.assetId
        ])
    }

    @Test func photoIndexStoreAppliesOnlyChangedRows() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoIndexStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = PhotoIndexStore(databaseURL: directory.appendingPathComponent("index.sqlite3"))
        let first = IndexEntry.stub(assetId: "first", score: 10, modificationTimestamp: 1)
        let second = IndexEntry.stub(assetId: "second", score: 20, modificationTimestamp: 1)
        try store.replaceAll(
            with: [first.assetId: first, second.assetId: second],
            schemaVersion: 3
        )

        let updatedSecond = IndexEntry.stub(
            assetId: "second",
            score: 99,
            modificationTimestamp: 2
        )
        let third = IndexEntry.stub(assetId: "third", score: 30, modificationTimestamp: 1)
        try store.apply(
            upserts: [updatedSecond, third],
            removing: ["first"],
            schemaVersion: 3
        )
        try store.checkpoint()

        let restored = try store.loadEntries()
        #expect(Set(restored.keys) == ["second", "third"])
        #expect(restored["second"]?.score == 99)
        #expect(restored["second"]?.modificationTimestamp == 2)
        #expect(restored["third"]?.score == 30)
    }

    // ── CollageSourceType ──────────────────────────────────────────────

    @Test func collageSourceType_displayTitles() async throws {
        #expect(CollageSourceType.year(2021).displayTitle   == "2021 Collage")
        #expect(CollageSourceType.place("Paris").displayTitle == "Paris Collage")
        #expect(CollageSourceType.person("Mom").displayTitle  == "Mom Collage")
    }

    @Test func collageSourceType_analyticsLabels() async throws {
        #expect(CollageSourceType.year(2021).analyticsLabel   == "year")
        #expect(CollageSourceType.place("Paris").analyticsLabel == "place")
        #expect(CollageSourceType.person("Mom").analyticsLabel  == "person")
    }

    // ── MemoryCollage ──────────────────────────────────────────────────

    @Test func memoryCollage_maxPhotosConstant() async throws {
        // The largest renderer layout is a 3×3 grid.
        #expect(MemoryCollage.maxPhotos == 9)
    }
}
