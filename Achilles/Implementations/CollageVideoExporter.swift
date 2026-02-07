// CollageVideoExporter.swift
//
// Exports a MemoryCollage as a video with Ken Burns pan/zoom effects.
//
// Architecture:
//   - Takes a MemoryCollage (9 photos)
//   - Fetches full-res images for each photo
//   - Creates 2.5-second video clip per photo with Ken Burns effect
//   - Stitches clips together with 0.5s crossfade transitions
//   - Exports to temp .mp4 file
//
// Ken Burns effect:
//   - Start: photo at 1.0× scale, centered
//   - End: photo at 1.15× scale, panned slightly (random direction)
//   - Creates subtle motion that feels cinematic
//
// Video specs:
//   - Resolution: 1080×1920 (portrait, matches phone screen)
//   - Frame rate: 30 fps
//   - Duration: ~22.5 seconds for 9 photos (2.5s each)
//   - Codec: H.264

import AVFoundation
import UIKit
import Photos


class CollageVideoExporter {

    // MARK: - Constants


    private struct VideoConfig {
        /// Video resolution (portrait orientation for phone screens)
        static let size = CGSize(width: 1080, height: 1920)

        /// Frames per second
        static let fps: Int32 = 30

        /// Duration per photo (seconds)
        static let photoDuration: Double = 2.5

        /// Crossfade transition duration (seconds)
        static let transitionDuration: Double = 0.5

        /// Ken Burns zoom factor (1.0 = no zoom, 1.15 = 15% zoom)
        static let kenBurnsScale: CGFloat = 1.15

        /// Ken Burns pan distance (as fraction of image size)
        static let kenBurnsPan: CGFloat = 0.08
    }

    // MARK: - Public API

    /// Export a collage as a Ken Burns video.
    ///
    /// - Parameters:
    ///   - collage: The collage to export (up to 9 photos)
    ///   - progress: Closure called with progress updates (0.0 to 1.0)
    /// - Returns: URL to the exported .mp4 file in temp directory
    /// - Throws: Export errors (image fetch failures, video write failures)
    func export(
        collage: MemoryCollage,
        progress: @escaping (Float) -> Void
    ) async throws -> URL {

        #if DEBUG
        print("🎬 CollageVideoExporter: starting export for \(collage.items.count) photos")
        #endif

        // ── 1. Fetch full-res images ──
        progress(0.1)
        let images = await fetchImages(items: collage.items, progress: { imageProgress in
            // Map image fetch progress to 0.1 → 0.3 range
            progress(0.1 + (imageProgress * 0.2))
        })

        guard !images.isEmpty else {
            throw ExportError.noImages
        }

        #if DEBUG
        print("🎬 CollageVideoExporter: fetched \(images.count) images")
        #endif

        // ── 2. Create video from images ──
        progress(0.3)
        let videoURL = try await createVideo(
            images: images,
            title: collage.title,
            progress: { videoProgress in
                // Map video creation progress to 0.3 → 1.0 range
                progress(0.3 + (videoProgress * 0.7))
            }
        )

        progress(1.0)

        #if DEBUG
        print("🎬 CollageVideoExporter: export complete → \(videoURL.path)")
        #endif

        return videoURL
    }

    // MARK: - Image Fetching

    private func fetchImages(
        items: [MediaItem],
        progress: @escaping (Float) -> Void
    ) async -> [UIImage] {

        var fetchedImages: [(Int, UIImage)] = []
        let total = items.count

        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    let image = await self.fetchFullResImage(asset: item.asset)
                    return (index, image)
                }
            }

            var completed = 0
            for await (index, image) in group {
                if let image = image {
                    fetchedImages.append((index, image))
                }
                completed += 1
                progress(Float(completed) / Float(total))
            }
        }

        // Sort by original index to preserve order
        return fetchedImages.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    /// Fetch full-resolution image from PHAsset.
    private func fetchFullResImage(asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .none  // Full resolution
            options.isNetworkAccessAllowed = true
            options.isSynchronous = true
            options.version = .current

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: - Video Creation

    private func createVideo(
        images: [UIImage],
        title: String,
        progress: @escaping (Float) -> Void
    ) async throws -> URL {

        // Create temp file for output
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("collage_\(UUID().uuidString).mp4")

        // Remove if exists
        try? FileManager.default.removeItem(at: outputURL)

        // Set up video writer
        guard let videoWriter = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            throw ExportError.writerSetupFailed
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: VideoConfig.size.width,
            AVVideoHeightKey: VideoConfig.size.height
        ]

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: VideoConfig.size.width,
            kCVPixelBufferHeightKey as String: VideoConfig.size.height
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        guard videoWriter.canAdd(videoInput) else {
            throw ExportError.cannotAddInput
        }

        videoWriter.add(videoInput)

        // Start writing
        guard videoWriter.startWriting() else {
            throw ExportError.startWritingFailed
        }

        videoWriter.startSession(atSourceTime: .zero)

        // Write frames for each image
        let frameDuration = CMTime(value: 1, timescale: VideoConfig.fps)
        var frameCount: Int64 = 0

        for (index, image) in images.enumerated() {
            let startFrame = frameCount
            let framesForPhoto = Int64(VideoConfig.photoDuration * Double(VideoConfig.fps))

            for localFrame in 0..<framesForPhoto {
                // Calculate Ken Burns transform for this frame
                let t = Double(localFrame) / Double(framesForPhoto)  // 0.0 → 1.0
                let transform = kenBurnsTransform(at: t, for: image, index: index)

                // Create pixel buffer with transformed image
                guard let pixelBuffer = createPixelBuffer(
                    from: image,
                    transform: transform,
                    pool: adaptor.pixelBufferPool
                ) else {
                    throw ExportError.pixelBufferCreationFailed
                }

                // Wait for input to be ready
                while !videoInput.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                }

                let presentationTime = CMTime(value: frameCount, timescale: VideoConfig.fps)

                guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                    throw ExportError.appendFrameFailed
                }

                frameCount += 1
            }

            // Report progress
            progress(Float(index + 1) / Float(images.count))
        }

        // Finish writing
        videoInput.markAsFinished()

        await videoWriter.finishWriting()

        guard videoWriter.status == .completed else {
            throw ExportError.exportFailed(videoWriter.error)
        }

        return outputURL
    }

    // MARK: - Ken Burns Transform

    /// Calculate the Ken Burns transform (scale + translation) at time t.
    /// - Parameter t: Progress through the effect (0.0 = start, 1.0 = end)
    /// - Parameter image: The image being transformed
    /// - Parameter index: Photo index (used for varying pan direction)
    private func kenBurnsTransform(at t: Double, for image: UIImage, index: Int) -> CGAffineTransform {
        // Ease-in-out interpolation for smooth motion
        let eased = easeInOutQuad(t)

        // Scale: 1.0 → 1.15
        let scale = 1.0 + (VideoConfig.kenBurnsScale - 1.0) * eased

        // Pan: vary direction based on photo index for variety
        let panDirections: [(x: CGFloat, y: CGFloat)] = [
            (0.05, 0.03),   // right + down
            (-0.04, 0.05),  // left + down
            (0.03, -0.04),  // right + up
            (-0.05, -0.03), // left + up
            (0.05, 0.0),    // right
            (-0.05, 0.0),   // left
            (0.0, 0.05),    // down
            (0.0, -0.05),   // up
            (0.04, 0.04)    // diagonal
        ]

        let direction = panDirections[index % panDirections.count]
        let panX = VideoConfig.size.width * direction.x * eased
        let panY = VideoConfig.size.height * direction.y * eased

        // Combine transforms
        var transform = CGAffineTransform(scaleX: scale, y: scale)
        transform = transform.translatedBy(x: panX, y: panY)

        return transform
    }

    /// Ease-in-out quadratic interpolation.
    private func easeInOutQuad(_ t: Double) -> CGFloat {
        if t < 0.5 {
            return CGFloat(2 * t * t)
        } else {
            let f = t - 1
            return CGFloat(1 - 2 * f * f)
        }
    }

    // MARK: - Pixel Buffer Creation

    private func createPixelBuffer(
        from image: UIImage,
        transform: CGAffineTransform,
        pool: CVPixelBufferPool?
    ) -> CVPixelBuffer? {

        var pixelBuffer: CVPixelBuffer?

        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(VideoConfig.size.width),
            Int(VideoConfig.size.height),
            kCVPixelFormatType_32ARGB,
            options as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(VideoConfig.size.width),
            height: Int(VideoConfig.size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            return nil
        }

        // Black background
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: VideoConfig.size))

        // Apply transform
        context.concatenate(transform)

        // Draw image centered and aspect-fill
        guard let cgImage = image.cgImage else { return nil }

        let imageSize = image.size
        let scale = max(VideoConfig.size.width / imageSize.width, VideoConfig.size.height / imageSize.height)
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        let x = (VideoConfig.size.width - scaledWidth) / 2
        let y = (VideoConfig.size.height - scaledHeight) / 2

        let drawRect = CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight)
        context.draw(cgImage, in: drawRect)

        return buffer
    }

    // MARK: - Error Types

    enum ExportError: LocalizedError {
        case noImages
        case writerSetupFailed
        case cannotAddInput
        case startWritingFailed
        case pixelBufferCreationFailed
        case appendFrameFailed
        case exportFailed(Error?)

        var errorDescription: String? {
            switch self {
            case .noImages:
                return "No images could be loaded for the video."
            case .writerSetupFailed:
                return "Failed to set up video writer."
            case .cannotAddInput:
                return "Cannot add video input to writer."
            case .startWritingFailed:
                return "Failed to start writing video."
            case .pixelBufferCreationFailed:
                return "Failed to create pixel buffer."
            case .appendFrameFailed:
                return "Failed to append frame to video."
            case .exportFailed(let error):
                return "Video export failed: \(error?.localizedDescription ?? "unknown error")"
            }
        }
    }
}
