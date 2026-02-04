// CollageRenderer.swift
//
// Composites up to 10 photos into a single UIImage using a uniform grid
// layout via Core Graphics.  This is the only place in the collage feature
// that touches pixel data.
//
// Design decisions
// ────────────────
//   - Resolution: each photo is requested at ~400 × 400 points (not full
//     res).  The final canvas is sized so the output is a crisp but
//     reasonably-sized image (roughly 1200 × 1200 for a 3×3+1 grid).
//   - Layout: uniform grid.  Rows fill left-to-right, last row may be
//     short.  Column count adapts to photo count:
//         1–4 photos  →  2 columns
//         5–9 photos  →  3 columns
//         10  photos  →  3 columns  (3+3+3+1)
//   - Memory: source images are loaded, drawn, and released within this
//     single call.  Nothing lingers in any cache after render.
//   - Threading: the caller (CollageViewModel) invokes this on a
//     background task.  All work here is synchronous and CPU-bound once
//     the images are in hand — no UIKit or main-thread requirements.

import UIKit
import Photos


class CollageRenderer {

    // MARK: - Constants

    private struct Layout {
        /// Target size for each individual photo request (points).
        static let thumbnailSize: CGSize = CGSize(width: 400, height: 400)

        /// Gap between cells in the grid (points).
        static let spacing: CGFloat = 6

        /// Corner radius of each cell.
        static let cellRadius: CGFloat = 8

        /// Background colour of the canvas.
        static let backgroundColor: UIColor = .systemGray6
    }

    // MARK: - Dependencies

    /// Closure the renderer uses to fetch a single image.  Injected so
    /// tests can stub it out without a real photo library.
    let fetchImage: (MediaItem) async -> UIImage?

    // MARK: - Init

    /// - Parameter fetchImage: async closure that loads one image for a
    ///   given MediaItem at collage-appropriate size.  The default
    ///   implementation uses PHCachingImageManager directly.
    init(fetchImage: @escaping (MediaItem) async -> UIImage? = CollageRenderer.defaultFetch) {
        self.fetchImage = fetchImage
    }

    /// Default fetch implementation — requests from PHImageManager at the
    /// collage thumbnail size.
    private static func defaultFetch(_ item: MediaItem) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode    = .highQualityFormat
            options.resizeMode      = .fast
            options.isNetworkAccessAllowed = true
            options.isSynchronous   = false
            options.version         = .current

            PHCachingImageManager.default().requestImage(
                for: item.asset,
                targetSize: Layout.thumbnailSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: - Public API

    /// Render a collage from the given items.
    ///
    /// - Parameter items: 1–10 MediaItems (score-sorted; order is preserved
    ///   in the grid, left-to-right, top-to-bottom).
    /// - Returns: A single composited UIImage, or nil if no images could
    ///   be loaded.
    func render(items: [MediaItem]) async -> UIImage? {
        guard !items.isEmpty else { return nil }

        let clamped = Array(items.prefix(MemoryCollage.maxPhotos))

        // ── 1. Load all images concurrently ──
        let images = await withTaskGroup(of: (Int, UIImage?).self, returning: [(Int, UIImage?)].self) { group in
            for (index, item) in clamped.enumerated() {
                group.addTask {
                    let img = await self.fetchImage(item)
                    return (index, img)
                }
            }
            var results = [(Int, UIImage?)]()
            results.reserveCapacity(clamped.count)
            for await result in group {
                results.append(result)
            }
            return results
        }

        // Re-sort by original index so grid order matches score order.
        let sorted = images.sorted { $0.0 < $1.0 }.compactMap { $0.1 }
        guard !sorted.isEmpty else {
            print("🖼️ CollageRenderer: all image fetches returned nil.")
            return nil
        }

        // ── 2. Compute layout ──
        let columns   = columnCount(for: sorted.count)
        let rows      = (sorted.count + columns - 1) / columns   // ceiling division
        let cellSize  = Layout.thumbnailSize
        let canvasW   = CGFloat(columns) * cellSize.width  + CGFloat(columns - 1) * Layout.spacing
        let canvasH   = CGFloat(rows)    * cellSize.height + CGFloat(rows    - 1) * Layout.spacing
        let canvasSize = CGSize(width: canvasW, height: canvasH)

        // ── 3. Composite onto a single image via UIGraphicsImageRenderer ──
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0   // 1× keeps output ~1200 px; bump to 2× for Retina export if needed.
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)

        let result: UIImage = renderer.image { ctx in
            // Fill background
            Layout.backgroundColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvasSize))

            for (i, image) in sorted.enumerated() {
                let col = i % columns
                let row = i / columns
                let x   = CGFloat(col) * (cellSize.width  + Layout.spacing)
                let y   = CGFloat(row) * (cellSize.height + Layout.spacing)
                let rect = CGRect(x: x, y: y, width: cellSize.width, height: cellSize.height)

                // Clip to rounded rectangle
                let cg = ctx.cgContext
                cg.saveGState()
                let clipPath = CGMutablePath()
                clipPath.addRoundedRect(in: rect, cornerWidth: Layout.cellRadius, cornerHeight: Layout.cellRadius)
                cg.addPath(clipPath)
                cg.clip()

                // Draw image, filling the cell (aspect-fill crop)
                let imgSize = image.size
                let imgScale = max(rect.width / imgSize.width, rect.height / imgSize.height)
                let drawW    = imgSize.width  * imgScale
                let drawH    = imgSize.height * imgScale
                let drawX    = rect.minX + (rect.width  - drawW) / 2
                let drawY    = rect.minY + (rect.height - drawH) / 2
                image.draw(in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))

                cg.restoreGState()
            }
        }

        // ── 4. Clean up — source images go out of scope here; ARC handles the rest ──
        print("🖼️ CollageRenderer: composed \(sorted.count) images into \(Int(canvasW))×\(Int(canvasH)) canvas.")
        return result
    }

    // MARK: - Private helpers

    /// How many columns for N photos.
    private func columnCount(for photoCount: Int) -> Int {
        switch photoCount {
        case 1...4: return 2
        default:    return 3
        }
    }

}
