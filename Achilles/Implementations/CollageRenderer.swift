// CollageRenderer.swift
//
// Composites up to 9 photos into a single UIImage using one of several
// layout styles via Core Graphics.  This is the only place in the collage
// feature that touches pixel data.
//
// Layouts
// ───────
//   - Grid:      uniform grid (2×2, 2×3, or 3×3)
//   - Magazine:  one large hero + smaller supporting photos in an L-shape
//   - Polaroid:  stacked, slightly rotated photos with white borders
//   - Film Strip: vertical film-negative aesthetic with sprocket holes
//
// Design decisions
// ────────────────
//   - Resolution: each photo is requested at ~450 × 600 points (portrait).
//   - Memory: source images are loaded, drawn, and released within this
//     single call.  Nothing lingers in any cache after render.
//   - Threading: the caller (CollageViewModel) invokes this on a
//     background task.  All work here is synchronous and CPU-bound once
//     the images are in hand.

import UIKit
import Photos


class CollageRenderer {

    // MARK: - Constants

    private struct LayoutConfig {
        /// Target size for each individual photo request (points).
        static let thumbnailSize: CGSize = CGSize(width: 450, height: 600)

        /// Gap between cells in the grid (points).
        static let spacing: CGFloat = 6

        /// Corner radius of each cell.
        static let cellRadius: CGFloat = 8

        /// Background colour of the canvas.
        static let backgroundColor: UIColor = .systemGray6

        /// Output scale for sharp exports.
        static let outputScale: CGFloat = 2.0
    }

    // MARK: - Dependencies

    /// Closure the renderer uses to fetch a single image.  Injected so
    /// tests can stub it out without a real photo library.
    let fetchImage: (MediaItem) async -> UIImage?

    // MARK: - Init

    init(fetchImage: @escaping (MediaItem) async -> UIImage? = CollageRenderer.defaultFetch) {
        self.fetchImage = fetchImage
    }

    private static func defaultFetch(_ item: MediaItem) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode    = .highQualityFormat
            options.resizeMode      = .fast
            options.isNetworkAccessAllowed = true
            options.isSynchronous   = false  // Must be false when isNetworkAccessAllowed is true to avoid iCloud deadlock
            options.version         = .current

            var didResume = false

            PHCachingImageManager.default().requestImage(
                for: item.asset,
                targetSize: LayoutConfig.thumbnailSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // When isSynchronous is false, this callback can fire
                // multiple times (degraded thumbnail first, then full quality).
                // Only resume the continuation once with the final result.
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded && !didResume {
                    didResume = true
                    continuation.resume(returning: image)
                }
            }
        }
    }

    // MARK: - Public API

    /// Render a collage from the given items using the specified layout.
    ///
    /// - Parameters:
    ///   - items: 1–9 MediaItems (score-sorted; order is preserved).
    ///   - layout: The visual layout style to use (defaults to `.grid`).
    /// - Returns: A single composited UIImage, or nil if no images could be loaded.
    func render(items: [MediaItem], layout: CollageLayout = .grid) async -> UIImage? {
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

        let sorted = images.sorted { $0.0 < $1.0 }.compactMap { $0.1 }
        guard !sorted.isEmpty else {
            #if DEBUG
            print("🖼️ CollageRenderer: all image fetches returned nil.")
            #endif
            return nil
        }

        // ── 2. Dispatch to layout-specific renderer ──
        let result: UIImage?
        switch layout {
        case .grid:      result = renderGrid(images: sorted)
        case .magazine:  result = renderMagazine(images: sorted)
        case .polaroid:  result = renderPolaroid(images: sorted)
        case .filmStrip: result = renderFilmStrip(images: sorted)
        }

        #if DEBUG
        print("🖼️ CollageRenderer: composed \(sorted.count) images with \(layout.displayName) layout.")
        #endif
        return result
    }

    // MARK: - Grid Layout

    private func renderGrid(images: [UIImage]) -> UIImage {
        let columns   = gridColumnCount(for: images.count)
        let rows      = (images.count + columns - 1) / columns
        let cellSize  = LayoutConfig.thumbnailSize
        let canvasW   = CGFloat(columns) * cellSize.width  + CGFloat(columns - 1) * LayoutConfig.spacing
        let canvasH   = CGFloat(rows)    * cellSize.height + CGFloat(rows    - 1) * LayoutConfig.spacing
        let canvasSize = CGSize(width: canvasW, height: canvasH)

        let format = UIGraphicsImageRendererFormat()
        format.scale = LayoutConfig.outputScale
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)

        return renderer.image { ctx in
            LayoutConfig.backgroundColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvasSize))

            for (i, image) in images.enumerated() {
                let col = i % columns
                let row = i / columns
                let x   = CGFloat(col) * (cellSize.width  + LayoutConfig.spacing)
                let y   = CGFloat(row) * (cellSize.height + LayoutConfig.spacing)
                let rect = CGRect(x: x, y: y, width: cellSize.width, height: cellSize.height)
                drawAspectFill(image: image, in: rect, cornerRadius: LayoutConfig.cellRadius, context: ctx.cgContext)
            }
        }
    }

    private func gridColumnCount(for photoCount: Int) -> Int {
        switch photoCount {
        case 1...4: return 2
        default:    return 3
        }
    }

    // MARK: - Magazine Layout

    private func renderMagazine(images: [UIImage]) -> UIImage {
        let sp = LayoutConfig.spacing
        let rects = magazineCellRects(for: images.count, spacing: sp)

        // Compute canvas from the union of all rects
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        for r in rects {
            maxX = max(maxX, r.maxX)
            maxY = max(maxY, r.maxY)
        }
        let canvasSize = CGSize(width: maxX, height: maxY)

        let format = UIGraphicsImageRendererFormat()
        format.scale = LayoutConfig.outputScale
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)

        return renderer.image { ctx in
            LayoutConfig.backgroundColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvasSize))

            for (i, image) in images.enumerated() {
                guard i < rects.count else { break }
                drawAspectFill(image: image, in: rects[i], cornerRadius: LayoutConfig.cellRadius, context: ctx.cgContext)
            }
        }
    }

    private func magazineCellRects(for count: Int, spacing sp: CGFloat) -> [CGRect] {
        // Hero is always top-left and large.
        // Supporting photos fill the right column and bottom row.
        let heroW: CGFloat = 600
        let heroH: CGFloat = 800
        let smallW: CGFloat = 296
        let smallH: CGFloat = (heroH - sp) / 2  // two cells stacked in right column

        let bottomCellH: CGFloat = 400

        switch count {
        case 1:
            return [CGRect(x: 0, y: 0, width: heroW, height: heroH)]

        case 2:
            return [
                CGRect(x: 0, y: 0, width: heroW, height: heroH),
                CGRect(x: heroW + sp, y: 0, width: smallW, height: heroH)
            ]

        case 3:
            return [
                CGRect(x: 0, y: 0, width: heroW, height: heroH),
                CGRect(x: heroW + sp, y: 0, width: smallW, height: smallH),
                CGRect(x: heroW + sp, y: smallH + sp, width: smallW, height: smallH)
            ]

        case 4:
            let totalW = heroW + sp + smallW
            return [
                CGRect(x: 0, y: 0, width: heroW, height: heroH),
                CGRect(x: heroW + sp, y: 0, width: smallW, height: smallH),
                CGRect(x: heroW + sp, y: smallH + sp, width: smallW, height: smallH),
                CGRect(x: 0, y: heroH + sp, width: totalW, height: bottomCellH)
            ]

        case 5...6:
            let totalW = heroW + sp + smallW
            let bottomCount = count - 3
            let bottomCellW = (totalW - CGFloat(bottomCount - 1) * sp) / CGFloat(bottomCount)
            var rects = [
                CGRect(x: 0, y: 0, width: heroW, height: heroH),
                CGRect(x: heroW + sp, y: 0, width: smallW, height: smallH),
                CGRect(x: heroW + sp, y: smallH + sp, width: smallW, height: smallH)
            ]
            for j in 0..<bottomCount {
                let x = CGFloat(j) * (bottomCellW + sp)
                rects.append(CGRect(x: x, y: heroH + sp, width: bottomCellW, height: bottomCellH))
            }
            return rects

        default: // 7-9
            let totalW = heroW + sp + smallW
            let bottomCount = min(count - 3, 6) // up to 6 in bottom rows
            let bottomPerRow = min(bottomCount, 3)
            let bottomRows = (bottomCount + bottomPerRow - 1) / bottomPerRow
            let bottomCellW = (totalW - CGFloat(bottomPerRow - 1) * sp) / CGFloat(bottomPerRow)

            var rects = [
                CGRect(x: 0, y: 0, width: heroW, height: heroH),
                CGRect(x: heroW + sp, y: 0, width: smallW, height: smallH),
                CGRect(x: heroW + sp, y: smallH + sp, width: smallW, height: smallH)
            ]

            for j in 0..<bottomCount {
                let row = j / bottomPerRow
                let col = j % bottomPerRow
                let x = CGFloat(col) * (bottomCellW + sp)
                let y = heroH + sp + CGFloat(row) * (bottomCellH + sp)
                rects.append(CGRect(x: x, y: y, width: bottomCellW, height: bottomCellH))
            }
            return rects
        }
    }

    // MARK: - Polaroid Layout

    private func renderPolaroid(images: [UIImage]) -> UIImage {
        let canvasSize = CGSize(width: 1000, height: 1300)
        let photoSize  = CGSize(width: 360, height: 480)
        let borderSide: CGFloat = 20
        let borderBottom: CGFloat = 60
        let cardW = photoSize.width + borderSide * 2
        let cardH = photoSize.height + borderSide + borderBottom

        // Deterministic rotations (degrees)
        let rotations: [CGFloat] = [0, -8, 5, -3, 7, -6, 4, -7, 3]
        // Offsets from center
        let offsets: [(dx: CGFloat, dy: CGFloat)] = [
            (0, 0), (-80, -40), (70, -60), (-60, 50), (90, 30),
            (-40, -80), (50, 70), (-90, 20), (30, -50)
        ]

        let cx = canvasSize.width / 2
        let cy = canvasSize.height / 2

        let format = UIGraphicsImageRendererFormat()
        format.scale = LayoutConfig.outputScale
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)

        return renderer.image { ctx in
            LayoutConfig.backgroundColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvasSize))

            let cg = ctx.cgContext

            // Draw back-to-front (last photo first, top photo last)
            for i in stride(from: images.count - 1, through: 0, by: -1) {
                let image = images[i]
                let rotation = rotations[i % rotations.count]
                let offset = offsets[i % offsets.count]

                let centerX = cx + offset.dx
                let centerY = cy + offset.dy
                let angle = rotation * .pi / 180

                cg.saveGState()

                // Translate to card center, rotate
                cg.translateBy(x: centerX, y: centerY)
                cg.rotate(by: angle)

                // Draw shadow
                cg.setShadow(offset: CGSize(width: 0, height: 4), blur: 12,
                             color: UIColor.black.withAlphaComponent(0.35).cgColor)

                // Draw white polaroid card
                let cardRect = CGRect(x: -cardW / 2, y: -cardH / 2, width: cardW, height: cardH)
                cg.setFillColor(UIColor.white.cgColor)
                let cardPath = CGMutablePath()
                cardPath.addRoundedRect(in: cardRect, cornerWidth: 4, cornerHeight: 4)
                cg.addPath(cardPath)
                cg.fillPath()

                // Clear shadow for photo drawing
                cg.setShadow(offset: .zero, blur: 0)

                // Draw photo inside the card
                let photoRect = CGRect(
                    x: -cardW / 2 + borderSide,
                    y: -cardH / 2 + borderSide,
                    width: photoSize.width,
                    height: photoSize.height
                )
                drawAspectFill(image: image, in: photoRect, cornerRadius: 0, context: cg)

                cg.restoreGState()
            }
        }
    }

    // MARK: - Film Strip Layout

    private func renderFilmStrip(images: [UIImage]) -> UIImage {
        let stripWidth: CGFloat = 500
        let frameWidth: CGFloat = 420
        let frameHeight: CGFloat = 280
        let frameBorder: CGFloat = 2
        let frameSpacing: CGFloat = 20
        let margin: CGFloat = 40
        let topPadding: CGFloat = 30
        let bottomPadding: CGFloat = 30
        let sprocketWidth: CGFloat = 20
        let sprocketHeight: CGFloat = 30
        let sprocketInset: CGFloat = 8

        let stripHeight = topPadding + CGFloat(images.count) * (frameHeight + frameSpacing) - frameSpacing + bottomPadding
        let canvasSize = CGSize(width: stripWidth, height: stripHeight)

        let stripColor = UIColor(white: 0.12, alpha: 1.0)
        let sprocketColor = UIColor.white.withAlphaComponent(0.25)

        let format = UIGraphicsImageRendererFormat()
        format.scale = LayoutConfig.outputScale
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)

        return renderer.image { ctx in
            let cg = ctx.cgContext

            // Dark strip background
            stripColor.setFill()
            cg.fill(CGRect(origin: .zero, size: canvasSize))

            for (i, image) in images.enumerated() {
                let y = topPadding + CGFloat(i) * (frameHeight + frameSpacing)

                // Sprocket holes (left and right) — rounded for authentic film look
                sprocketColor.setFill()
                let sprocketY = y + (frameHeight - sprocketHeight) / 2
                let sprocketRadius: CGFloat = 4
                let leftSprocket = CGRect(x: sprocketInset, y: sprocketY, width: sprocketWidth, height: sprocketHeight)
                let rightSprocket = CGRect(x: stripWidth - sprocketInset - sprocketWidth, y: sprocketY, width: sprocketWidth, height: sprocketHeight)
                let leftPath = CGMutablePath()
                leftPath.addRoundedRect(in: leftSprocket, cornerWidth: sprocketRadius, cornerHeight: sprocketRadius)
                cg.addPath(leftPath)
                cg.fillPath()
                let rightPath = CGMutablePath()
                rightPath.addRoundedRect(in: rightSprocket, cornerWidth: sprocketRadius, cornerHeight: sprocketRadius)
                cg.addPath(rightPath)
                cg.fillPath()

                // White frame border
                let borderRect = CGRect(
                    x: margin - frameBorder,
                    y: y - frameBorder,
                    width: frameWidth + frameBorder * 2,
                    height: frameHeight + frameBorder * 2
                )
                UIColor.white.withAlphaComponent(0.5).setFill()
                cg.fill(borderRect)

                // Photo (sharp corners for film aesthetic)
                let photoRect = CGRect(x: margin, y: y, width: frameWidth, height: frameHeight)
                drawAspectFill(image: image, in: photoRect, cornerRadius: 0, context: cg)
            }
        }
    }

    // MARK: - Shared Drawing Helper

    /// Draws an image into a rect with aspect-fill cropping and optional corner radius.
    private func drawAspectFill(image: UIImage, in rect: CGRect, cornerRadius: CGFloat, context: CGContext) {
        context.saveGState()

        if cornerRadius > 0 {
            let clipPath = CGMutablePath()
            clipPath.addRoundedRect(in: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius)
            context.addPath(clipPath)
            context.clip()
        }

        let imgSize  = image.size
        let imgScale = max(rect.width / imgSize.width, rect.height / imgSize.height)
        let drawW    = imgSize.width  * imgScale
        let drawH    = imgSize.height * imgScale
        let drawX    = rect.minX + (rect.width  - drawW) / 2
        let drawY    = rect.minY + (rect.height - drawH) / 2
        image.draw(in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))

        context.restoreGState()
    }
}
