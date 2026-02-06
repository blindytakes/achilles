# Throwbacks Memory Collage Feature — PRD

> **Note:** This document is the *original* design spec. Sections that differ from the shipped v1 implementation are marked with `[v1 delta]` inline. See also **Deferred to Post-V1** at the bottom for a consolidated list of what didn't ship in the first cut.

## Overview

A feature for the Throwbacks iOS app that lets users generate photo collages from their memories. Users select a year, place, or person and the app creates a shareable collage image from their best photos matching that source.

**Core principle:** Everything runs on-device. No cloud compute, no data leaves the phone.

---

## User Experience

### Flow

1. User opens Throwbacks and taps "Create Memory"
2. User sees a picker with two tabs: **People** and **Themes** `[v1 delta: single picker with Year / Place / Person chip rows; Place and Person rows only appear when index data is available]`
3. User selects a person (e.g., "Jake") or theme (e.g., "Beach") `[v1 delta: user selects a year, place, or person]`
4. User optionally adjusts date range filter `[v1 delta: not shipped — no date-range filter in v1]`
5. App generates a 6-photo collage with face-aware cropping `[v1 delta: up to 10 photos, uniform grid, no face-aware cropping]`
6. User sees preview with shuffle/save/share buttons `[v1 delta: Save and Regenerate only; share sheet not shipped]`
7. On save, collage is added to Camera Roll

### Picker Requirements

- **People tab**: Display all People albums with >= 10 photos `[v1 delta: People row shown when index has people data; no minimum-count gate]`
- **Themes tab**: Show auto-generated clusters (beaches, mountains, food, etc.) — deferred to post-v1
- **Date range filter**: Slider with "All time / Last year / Last 5 years" presets `[v1 delta: not shipped]`

### Collage Output

- **Aspect ratio**: 4:5 rectangle (optimized for full screen viewing) `[v1 delta: square canvas; column count adapts to photo count (2-col for 1–4 photos, 3-col for 5+)]`
- **Photo count**: 6 photos (2x3 grid) `[v1 delta: up to 10 photos, dynamic grid]`
- **Quality**: High resolution, suitable for saving and sharing `[v1 delta: 1× scale (~1200 px); bump to 2× noted as future option]`
- **Save behavior**: Only on explicit user tap (not auto-saved) ✓ shipped as designed
- **Shuffle**: Deterministic with seed (user can shuffle to see different combinations) `[v1 delta: Regenerate re-queries the index; no seed-based deterministic shuffle]`

---

## Technical Architecture

### Core Data Model

`[v1 delta: Core Data was not used. The index is a single [String: IndexEntry] dictionary persisted as JSON in the app's cache directory. See IndexEntry and IndexPersistencePayload in PhotoIndexService.swift.]`

Original spec (target for future iterations):

```swift
// Stores photo metadata for fast lookups
@Model
class PhotoIndex {
    var assetID: String              // PHAsset local identifier
    var creationDate: Date
    var embedding: [Float]?          // Vision scene embedding (2048 dims)
    var sceneLabels: [String]        // ["beach", "sunset", "outdoor"]
    var aestheticScore: Float?       // 0.0-1.0 from VNCalculateImageAestheticsScoresRequest
    var hasFaces: Bool
    var faceBoundingBoxes: Data?     // Encoded CGRect array
}

// Caches People album mappings
@Model
class PersonCache {
    var personID: String             // PHAssetCollection local identifier
    var displayName: String
    var photoCount: Int
    var lastUpdated: Date
}

// Future: Theme clusters (post-v1)
@Model
class ThemeCluster {
    var clusterID: UUID
    var themeName: String            // "Beach", "Food", etc.
    var photoIDs: [String]           // Array of assetIDs
    var centroid: [Float]            // Cluster center in embedding space
}
```

### Background Indexing Pipeline

`[v1 delta: No BGProcessingTask or Vision pipeline. The index is built synchronously on a detached background task the first time the collage tab appears. Scoring is a fast heuristic (O(1) per asset) based on PHAsset metadata — see calculateScore() in PhotoIndexService. Incremental updates are handled via PHPhotoLibraryChangeObserver. A monthly full rebuild runs as a safety net.]`

Original spec (target for future iterations):

Uses `BGProcessingTask` to index photos incrementally:

1. Request all `PHAsset` objects from Photos library
2. For each photo:
   - Run Vision classification → extract scene labels
   - Run Vision embeddings → store 2048-dim vector
   - Run Vision face detection → store bounding boxes
   - Run Vision aesthetics scoring → store quality score
3. Save to Core Data in batches
4. Update PersonCache from Apple's People albums

**Performance targets:**
- Process ~100 photos/min on iPhone 12
- Complete indexing for 20k photos in ~48 hours
- Use low priority queue to avoid draining battery

### Photo Selection Algorithm

`[v1 delta: simplified. CollageSourceService asks the index for the top-N items matching the source (year / place / person). The index returns them pre-sorted by heuristic score. No aesthetics threshold, no date-spread logic, no face-visibility filter. Max 10 photos returned.]`

Original spec (target for future iterations):

When user selects a person or theme:

1. **Candidate pool**: Query Core Data for all photos matching criteria
2. **Filter**: Only include photos with `aestheticScore > 0.5`
3. **Date spread**: Sort by creation date, select photos spread across time range
4. **For People collages**: Filter for photos where face bounding box is > 15% of image area
5. **Rank by quality**: Sort by aesthetics score
6. **Select top 8-10**: Keep extras in case iCloud photos fail to download

### Face-Aware Cropping

`[v1 delta: not shipped. CollageRenderer uses a uniform aspect-fill crop (center-weighted) for every cell. Face-aware cropping is deferred to post-v1.]`

Original spec (target for future iterations):

For each photo in the collage:

1. Load full resolution image via `PHImageManager`
2. Get face bounding box from Core Data
3. Calculate crop rect that:
   - Centers on face
   - Maintains 4:5 aspect ratio
   - Ensures face is fully visible
   - Fallback to center crop if no face detected
4. Render cropped image into collage grid

### Collage Rendering

- Use `UIGraphicsImageRenderer` to composite final image ✓ shipped as designed
- 2x3 grid layout with minimal spacing `[v1 delta: dynamic grid — 2 columns for 1–4 photos, 3 columns for 5+. 6 pt spacing, 8 pt rounded corners.]`
- Target resolution: 1200x1500px (4:5 ratio at ~@3x scale) `[v1 delta: ~1200×1200 square at 1× scale]`
- Export as JPEG at 0.9 quality `[v1 delta: saved as UIImage via PHAssetCreationRequest; format is determined by Photos framework]`

---

## Build Phases

### Phase 1: Foundation (Week 1)
1. Set up Core Data models (`PhotoIndex`, `PersonCache`)
2. Create `PersistenceController` for Core Data stack
3. Request Photos library permissions
4. Basic photo fetch via `PHAsset`

### Phase 2: Indexing Pipeline (Week 2)
1. Set up `BGProcessingTask` for background work
2. Implement Vision classification pipeline
3. Implement Vision embeddings extraction
4. Implement face detection and bounding box storage
5. Implement aesthetics scoring
6. Batch save to Core Data

### Phase 3: People Picker UI (Week 3)
1. Enumerate People albums via `PHAssetCollection`
2. Populate `PersonCache` with counts
3. Build `MemoryPickerView` with People grid
4. Add tap handling to select person

### Phase 4: Photo Selection (Week 4)
1. Implement candidate filtering by person/theme
2. Implement date spread logic
3. Implement face visibility filtering
4. Rank by aesthetics score

### Phase 5: Collage Generation (Week 5)
1. Implement face-aware cropping logic
2. Build 2x3 grid layout renderer
3. Implement high-res image loading
4. Handle iCloud photo failures gracefully

### Phase 6: Preview & Actions (Week 6)
1. Build `CollagePreviewView` UI
2. Implement shuffle (increment seed, regenerate)
3. Implement save to Camera Roll
4. Implement share sheet

### Phase 7: Polish (Week 7)
1. Empty states ("No People albums found")
2. Loading indicators during generation
3. Error handling for all failure modes
4. Performance optimization (lazy loading, image caching)

### Phase 8: Testing (Week 8)
1. Test with small photo libraries (<100 photos)
2. Test with large libraries (20k+ photos)
3. Test edge cases (no faces, all low quality photos, etc.)
4. Test on older devices (iPhone 12, SE)

### Phase 9: Iteration (Post-launch)
1. Monitor crash reports and user feedback
2. Add Theme clustering (DBSCAN on embeddings)
3. Add more collage layouts (3x3, 4x4, etc.)
4. Add text overlays (date ranges, person names)

### Phase 10: Future Features
- iCloud photo support (download before rendering)
- Video support (animated slideshows)
- Custom aspect ratios (square, story format)
- iPad support with larger grids
- Export as wallpaper-optimized images

---

## Technical Constraints

### iCloud Photo Library Handling

**Decision for v1**: Only use photos that are **already downloaded locally**

- Check `PHAsset` availability before requesting image
- Use `PHImageManager` with `deliveryMode = .highQualityFormat`
- If photo is not available, skip to next candidate
- Pre-fetch 8-10 candidates to handle failures gracefully

**Future enhancement**: Trigger download for iCloud photos and show loading state

### Performance Considerations

| Device | Indexing Speed | Collage Generation |
|--------|----------------|-------------------|
| iPhone 15 Pro | ~200 photos/min | < 1 second |
| iPhone 14 | ~150 photos/min | < 2 seconds |
| iPhone 12 | ~100 photos/min | < 3 seconds |
| iPhone SE (3rd gen) | ~80 photos/min | < 5 seconds |

### Storage Budget

| Data | Size per Photo | 20k Photos |
|------|----------------|------------|
| Embedding (2048 floats) | ~8KB | ~160MB |
| Face bounding box | ~32 bytes | ~640KB |
| Labels + metadata | ~200 bytes | ~4MB |
| **Total** | ~8.2KB | **~165MB** |

Acceptable for on-device storage. Offer cache clear option in settings.

### Memory During Processing

- Load embeddings in batches for clustering (not all 20k at once)
- Process photos in chunks during indexing
- Release images immediately after Vision analysis

---

## Open Questions (Resolved)

| Question | Decision |
|----------|----------|
| Minimum photo count for picker | 10 |
| Default collage size | 6 photos |
| Aspect ratio | 4:5 rectangle |
| iCloud handling | Local photos only (v1) |
| Storage layer | Core Data |
| Save behavior | Explicit only |
| Shuffle behavior | Deterministic with seed |
| iOS version target | iOS 17+ |

---

## Dependencies

- **iOS 17+** — required for `VNCalculateImageAestheticsScoresRequest`
- **Photos framework** — `PHAsset`, `PHAssetCollection`, `PHImageManager`
- **Vision framework** — classification, embeddings, face detection
- **Core Data** — persistence
- **Accelerate** — vector math for cosine similarity (optional optimization)

No third-party dependencies required for v1.

---

## Success Metrics

- User can generate a people collage in < 3 seconds (after initial indexing)
- Face visibility: 95%+ of people collage photos show the person's face clearly
- Indexing completes within 48 hours for libraries up to 50k photos
- App size increase < 5MB (no bundled ML models)

---

## Deferred to Post-V1

**From original spec (not yet implemented):**
- Vision-based indexing pipeline (embeddings, scene labels, face detection, aesthetics scoring)
- Core Data persistence layer (currently JSON in cache directory)
- BGProcessingTask background indexing
- Face-aware cropping
- Theme clustering (beaches, food, mountains, etc.) via DBSCAN on embeddings
- Date-range filter in the picker
- Deterministic seed-based shuffle
- Share sheet
- Minimum photo-count gate on picker rows
- 4:5 aspect ratio / fixed 2×3 grid layout
- 2× Retina export resolution

**Additional future work:**
- Video support / animated slideshows
- Text overlays (dates, person names, locations)
- iPad optimization with larger grids
- iCloud photo auto-download
- Export as live wallpaper or widget content

---

## References

- [Vision Framework Documentation](https://developer.apple.com/documentation/vision)
- [Photos Framework Documentation](https://developer.apple.com/documentation/photokit)
- [BGProcessingTask Documentation](https://developer.apple.com/documentation/backgroundtasks)
- [DBSCAN Algorithm](https://en.wikipedia.org/wiki/DBSCAN)
