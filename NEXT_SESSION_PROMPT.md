# Throwbaks (Achilles) — Photo/Video Loading Performance Improvements

## Project Context
Throwbaks is an iOS photo memory app (SwiftUI, Swift). The codebase lives at `/Users/alexsalesi/Documents/Throwbaks/Achilles` and is accessible via filesystem MCP. GitHub repo: `blindytakes/Throwbaks`.

The app shows photos from today's date in previous years. Users see a year carousel on launch, then swipe between year pages showing a grid of photos. Tapping a photo opens a detail view with zoom, Live Photo playback, video playback, and location info.

## Architecture Overview
- **PhotoViewModel** (`ViewModels/PhotoViewModel.swift`) — the core engine. Handles year scanning, page loading, prefetching, image/video requests, and caching coordination. Uses `PHCachingImageManager`.
- **ImageCacheService** (`Implementations/ImageCacheService.swift`) — NSCache-based caching with separate thumbnail (200 items/600MB), high-res (50 items/600MB), and Live Photo (20 items) caches.
- **GridItemView** (`Components/GridItemView.swift`) — grid cell that requests thumbnails on appear.
- **ItemDisplayView** (`Components/ItemDisplayView.swift`) — full-screen detail view for photos/videos/Live Photos.
- **MediaDetailView** (`Views/Media/MediaDetailView.swift`) — paged detail view wrapping ItemDisplayView, manages video player lifecycle.
- Protocol-oriented: `PhotoLibraryServiceProtocol`, `ImageCacheServiceProtocol`, `FeaturedSelectorServiceProtocol`, etc.

## Current Loading Pipeline
1. **Year scan**: Phase 1 scans years 1-4 (foreground), Phase 2 scans 5-20 (background). Uses `fetchLimit: 1` to check existence.
2. **Page load**: Fetches up to 300 items per year-date, picks featured item via scoring, samples 20 for display.
3. **Thumbnails**: GridItemView requests on appear, sized to cell dimensions. Cached in thumbnail NSCache.
4. **Prefetch**: When viewing year N, prefetches years N-1 and N+1 — loads page data, featured image (full-res), and first 10 thumbnails.
5. **Detail view**: Loads full-res image via `requestFullSizeImage` (highQualityFormat, blocks until ready). Videos load via `requestVideoURL` → `AVURLAsset`. Live Photos via `requestLivePhoto`.

## What Needs to Be Done (3 improvements)

### 1. Progressive image loading in detail view (highest priority)
**Problem:** When tapping a photo in the grid, `ItemDisplayView` shows a loading spinner until the full-resolution image is fetched (`deliveryMode: .highQualityFormat`). This creates a visible delay.

**Solution:** Use `.opportunistic` delivery mode so the system returns a degraded/thumbnail-quality image immediately, then delivers the full-res version when ready. Or, since the thumbnail is likely already in the ImageCacheService thumbnail cache from the grid view, show that cached thumbnail instantly as a placeholder while the full-res loads.

**Files to modify:**
- `ViewModels/PhotoViewModel.swift` — `requestFullSizeImage()` method
- `Components/ItemDisplayView.swift` — `loadMediaData()` to handle progressive updates

### 2. Use `startCachingImages(for:)` in prefetch pipeline
**Problem:** `PhotoViewModel` uses `PHCachingImageManager` but never calls its key method `startCachingImages(for:targetSize:contentMode:options:)`. The manual prefetch system works but doesn't leverage the system's ability to pre-decode images before they're requested.

**Solution:** In `triggerPrefetch` / `prefetchIfNeeded`, after fetching MediaItems for adjacent years, call `imageManager.startCachingImages(for: assets, targetSize: thumbnailSize, ...)`. Also call `stopCachingImages` when years go out of range.

**Files to modify:**
- `ViewModels/PhotoViewModel.swift` — `prefetchIfNeeded()` and `triggerPrefetch()` methods

### 3. Prefetch video URLs for adjacent items in detail pager
**Problem:** In `MediaDetailView`, when swiping to a video in the paged detail view, `updatePlayerForCurrentIndex()` calls `requestVideoURL()` which fetches the AVURLAsset on demand. There's a visible delay before playback starts.

**Solution:** When the detail view opens or when the current index changes, prefetch video URLs for items at `currentIndex ± 1`. Store them in a small dictionary cache. When the user swipes to a video, the URL is already available.

**Files to modify:**
- `Views/Media/MediaDetailView.swift` — add prefetch logic around `currentItemIndex` changes
- Possibly `ViewModels/PhotoViewModel.swift` — if adding a video URL cache

## Important Constraints
- The app is currently working and stable. Don't break existing functionality.
- Use `debugLog()` instead of `print()` for any logging (it compiles away in Release builds). The function is in `Core/DebugLog.swift`.
- Use `NavigationStack` not `NavigationView` (already migrated).
- All view models use `@MainActor`.
- The filesystem MCP has access to the full project. Read the relevant files before making changes.
- Test changes don't break the existing cache hit paths — the thumbnail and high-res caches in ImageCacheService should continue to work as they do now.
