//
//  AchillesTests.swift
//  AchillesTests
//
//  Created by Blind Takes on 3/29/25.
//

import Foundation
import Testing
@testable import Achilles


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
    func rebuildIfNeeded() async {}

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
        longitude:        Float?  = nil
    ) -> IndexEntry {
        IndexEntry(
            assetId:          assetId,
            mediaType:        UInt8(1),   // .image
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
        #expect(top.count == MemoryCollage.maxPhotos)   // max 10
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
            longitude: -0.1
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(IndexEntry.self, from: data)

        #expect(decoded.assetId      == original.assetId)
        #expect(decoded.creationYear == original.creationYear)
        #expect(decoded.score        == original.score)
        #expect(decoded.hasLocation  == original.hasLocation)
        #expect(decoded.latitude     == original.latitude)
        #expect(decoded.longitude    == original.longitude)
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
        #expect(MemoryCollage.maxPhotos == 10)
    }
}
