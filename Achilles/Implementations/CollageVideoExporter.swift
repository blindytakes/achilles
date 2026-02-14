// CollageVideoExporter.swift
//
// Exports a MemoryCollage as a video with Ken Burns pan/zoom effects
// and optional background music.
//
// Architecture:
//   - Takes a MemoryCollage (9 photos) + optional MusicTrack
//   - Fetches full-res images for each photo
//   - Creates 3.5-second video clip per photo with Ken Burns effect
//   - Alternates zoom-in / zoom-out between photos for variety
//   - If music selected: mixes audio via AVMutableComposition with
//     fade-in (first 1s) and fade-out (last 2s)
//   - Exports to temp .mp4 file
//
// Ken Burns effect:
//   - Even photos: zoom in from 1.0× to 1.07×, with gentle pan
//   - Odd photos: zoom out from 1.07× to 1.0×, with gentle pan
//   - Smoothstep easing for natural, cinematic motion
//
// Video specs:
//   - Resolution: 1080×1920 (portrait, matches phone screen)
//   - Frame rate: 30 fps
//   - Duration: ~31.5 seconds for 9 photos (3.5s each)
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
        static let photoDuration: Double = 3.5

        /// Crossfade transition duration between photos (seconds)
        static let crossfadeDuration: Double = 0.5

        /// Ken Burns zoom factor (1.0 = no zoom, 1.07 = 7% zoom)
        static let kenBurnsScale: CGFloat = 1.07
    }

    // MARK: - Public API

    /// Audio fade durations for background music.
    private struct AudioConfig {
        static let fadeInDuration:  Double = 1.0   // seconds
        static let fadeOutDuration: Double = 2.0   // seconds
    }

    /// Export a collage as a Ken Burns video with optional background music.
    ///
    /// - Parameters:
    ///   - collage: The collage to export (up to 9 photos)
    ///   - musicTrack: Background music track (`.none` for silent video)
    ///   - progress: Closure called with progress updates (0.0 to 1.0)
    /// - Returns: URL to the exported .mp4 file in temp directory
    /// - Throws: Export errors (image fetch failures, video write failures)
    func export(
        collage: MemoryCollage,
        musicTrack: MusicTrack = .none,
        progress: @escaping (Float) -> Void
    ) async throws -> URL {

        #if DEBUG
        print("🎬 CollageVideoExporter: starting export for \(collage.items.count) photos, music: \(musicTrack.displayName)")
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

        // ── 2. Create silent video from images ──
        progress(0.3)
        let silentVideoURL = try await createVideo(
            images: images,
            title: collage.title,
            progress: { videoProgress in
                // Map video creation progress to 0.3 → 0.9 range
                progress(0.3 + (videoProgress * 0.6))
            }
        )

        // ── 3. Mix in background music if selected ──
        let finalURL: URL
        if let audioURL = musicTrack.url {
            progress(0.9)
            #if DEBUG
            print("🎬 CollageVideoExporter: mixing audio track → \(musicTrack.rawValue)")
            #endif
            finalURL = try await mixAudio(audioURL: audioURL, intoVideo: silentVideoURL)
            // Clean up the silent intermediate file
            try? FileManager.default.removeItem(at: silentVideoURL)
        } else {
            finalURL = silentVideoURL
        }

        progress(1.0)

        #if DEBUG
        print("🎬 CollageVideoExporter: export complete → \(finalURL.path)")
        #endif

        return finalURL
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
            options.isSynchronous = false  // Must be false when isNetworkAccessAllowed is true to avoid deadlock
            options.version = .current

            var didResume = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                guard !didResume else { return }

                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let error = info?[PHImageErrorKey] as? Error

                // Resume on: non-degraded result, error, cancellation, or
                // if we got an image (even degraded) as a safety net so the
                // continuation never hangs.
                if !isDegraded || isCancelled || error != nil {
                    didResume = true
                    continuation.resume(returning: image)
                } else if isDegraded && image != nil {
                    // Schedule a fallback: if the high-quality callback never
                    // arrives within 5 seconds, use the degraded image.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                        guard !didResume else { return }
                        didResume = true
                        #if DEBUG
                        print("⚠️ CollageVideoExporter: using degraded image for asset (timeout)")
                        #endif
                        continuation.resume(returning: image)
                    }
                }
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

        // Write frames for each image, with crossfade transitions
        var frameCount: Int64 = 0
        let framesPerPhoto = Int64(VideoConfig.photoDuration * Double(VideoConfig.fps))
        let crossfadeFrames = Int64(VideoConfig.crossfadeDuration * Double(VideoConfig.fps))

        for (index, image) in images.enumerated() {
            let nextImage: UIImage? = (index + 1 < images.count) ? images[index + 1] : nil

            for localFrame in 0..<framesPerPhoto {
                let t = Double(localFrame) / Double(framesPerPhoto)  // 0.0 → 1.0
                let transform = kenBurnsTransform(at: t, for: image, index: index)

                // Check if we're in the crossfade zone (last 0.5s of this photo)
                let framesUntilEnd = framesPerPhoto - localFrame
                let inCrossfade = (framesUntilEnd <= crossfadeFrames) && (nextImage != nil)

                let pixelBuffer: CVPixelBuffer?

                if inCrossfade, let next = nextImage {
                    // Blend outgoing photo with incoming photo
                    let fadeProgress = Double(crossfadeFrames - framesUntilEnd) / Double(crossfadeFrames)  // 0.0 → 1.0
                    let nextT = fadeProgress * (Double(crossfadeFrames) / Double(framesPerPhoto))  // early progress into next photo
                    let nextTransform = kenBurnsTransform(at: nextT, for: next, index: index + 1)
                    pixelBuffer = createCrossfadePixelBuffer(
                        from: image, transform: transform,
                        to: next, nextTransform: nextTransform,
                        blend: CGFloat(fadeProgress),
                        pool: adaptor.pixelBufferPool
                    )
                } else {
                    pixelBuffer = createPixelBuffer(
                        from: image,
                        transform: transform,
                        pool: adaptor.pixelBufferPool
                    )
                }

                guard let buffer = pixelBuffer else {
                    throw ExportError.pixelBufferCreationFailed
                }

                // Wait for input to be ready
                while !videoInput.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                }

                let presentationTime = CMTime(value: frameCount, timescale: VideoConfig.fps)

                guard adaptor.append(buffer, withPresentationTime: presentationTime) else {
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
    ///
    /// Zooms from the center of the frame (not the origin) using a
    /// translate-scale-translate pattern.  Even-indexed photos zoom in,
    /// odd-indexed photos zoom out, for visual variety.
    ///
    /// - Parameter t: Progress through the effect (0.0 = start, 1.0 = end)
    /// - Parameter image: The image being transformed
    /// - Parameter index: Photo index (used for varying pan direction and zoom direction)
    private func kenBurnsTransform(at t: Double, for image: UIImage, index: Int) -> CGAffineTransform {
        let eased = smoothstep(t)

        // Center of the video frame — the anchor point for zoom
        let cx = VideoConfig.size.width / 2
        let cy = VideoConfig.size.height / 2

        // Alternate zoom direction: even photos zoom in, odd zoom out
        let zoomIn = (index % 2 == 0)
        let startScale: CGFloat = zoomIn ? 1.0 : VideoConfig.kenBurnsScale
        let endScale: CGFloat   = zoomIn ? VideoConfig.kenBurnsScale : 1.0
        let scale = startScale + (endScale - startScale) * eased

        // Gentle pan directions — subtle drift, not a swipe
        let panDirections: [(x: CGFloat, y: CGFloat)] = [
            ( 0.02,  0.01),    // right + slight down
            (-0.02,  0.015),   // left + slight down
            ( 0.015, -0.02),   // right + up
            (-0.015, -0.01),   // left + up
            ( 0.02,  0.0),     // right
            (-0.02,  0.0),     // left
            ( 0.0,   0.02),    // down
            ( 0.0,  -0.02),    // up
            ( 0.015,  0.015)   // diagonal
        ]

        let direction = panDirections[index % panDirections.count]
        let panX = VideoConfig.size.width  * direction.x * eased
        let panY = VideoConfig.size.height * direction.y * eased

        // Build transform: zoom from center + pan.
        //
        // Matrix: T(pan) * T(center) * S(scale) * T(-center)
        // Effect on point p: pan + center + scale * (p - center)
        //                  = scale * p + (1 - scale) * center + pan
        //
        // This ensures scaling happens around the center of the frame,
        // not the origin (0,0), which would cause drift toward the corner.
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: panX, y: panY)
        transform = transform.translatedBy(x: cx, y: cy)
        transform = transform.scaledBy(x: scale, y: scale)
        transform = transform.translatedBy(x: -cx, y: -cy)

        return transform
    }

    /// Smoothstep (Hermite) interpolation — gentler than quadratic ease-in-out.
    private func smoothstep(_ t: Double) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        return CGFloat(clamped * clamped * (3 - 2 * clamped))
    }

    // MARK: - Pixel Buffer Creation

    private func createPixelBuffer(
        from image: UIImage,
        transform: CGAffineTransform,
        pool: CVPixelBufferPool?
    ) -> CVPixelBuffer? {

        var pixelBuffer: CVPixelBuffer?

        // Prefer the pool (recycles buffers, avoids memory spikes).
        // Fall back to manual creation only if pool is nil.
        if let pool = pool {
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
            guard status == kCVReturnSuccess else { return nil }
        } else {
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
            guard status == kCVReturnSuccess else { return nil }
        }

        guard let buffer = pixelBuffer else { return nil }

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

    /// Create a pixel buffer blending two images for a crossfade transition.
    ///
    /// Draws the outgoing image at `(1 - blend)` alpha, then the incoming
    /// image at `blend` alpha on top.  When `blend` is 0 you see only the
    /// outgoing image; when 1 you see only the incoming image.
    private func createCrossfadePixelBuffer(
        from outgoing: UIImage, transform outTransform: CGAffineTransform,
        to incoming: UIImage, nextTransform inTransform: CGAffineTransform,
        blend: CGFloat,
        pool: CVPixelBufferPool?
    ) -> CVPixelBuffer? {

        var pixelBuffer: CVPixelBuffer?

        if let pool = pool {
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
            guard status == kCVReturnSuccess else { return nil }
        } else {
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
            guard status == kCVReturnSuccess else { return nil }
        }

        guard let buffer = pixelBuffer else { return nil }

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

        // Helper: draw an image with a given transform and alpha
        func drawImage(_ image: UIImage, transform: CGAffineTransform, alpha: CGFloat) {
            guard let cgImage = image.cgImage else { return }
            context.saveGState()
            context.setAlpha(alpha)
            context.concatenate(transform)

            let imageSize = image.size
            let s = max(VideoConfig.size.width / imageSize.width, VideoConfig.size.height / imageSize.height)
            let w = imageSize.width * s
            let h = imageSize.height * s
            let x = (VideoConfig.size.width - w) / 2
            let y = (VideoConfig.size.height - h) / 2

            context.draw(cgImage, in: CGRect(x: x, y: y, width: w, height: h))
            context.restoreGState()
        }

        // Draw outgoing image fading out, then incoming image fading in
        drawImage(outgoing, transform: outTransform, alpha: 1.0 - blend)
        drawImage(incoming, transform: inTransform, alpha: blend)

        return buffer
    }

    // MARK: - Audio Mixing

    /// Combines a silent video with a background music track using AVMutableComposition.
    ///
    /// The audio is trimmed to match the video duration, with a fade-in at the
    /// start and fade-out at the end for a polished feel.  If the audio track
    /// is shorter than the video, it loops.
    private func mixAudio(audioURL: URL, intoVideo videoURL: URL) async throws -> URL {

        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)

        let composition = AVMutableComposition()

        // ── Add video track ──
        guard let videoAssetTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let compositionVideoTrack = composition.addMutableTrack(
                  withMediaType: .video,
                  preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw ExportError.audioMixFailed
        }

        let videoDuration = try await videoAsset.load(.duration)
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoDuration),
            of: videoAssetTrack,
            at: .zero
        )

        // ── Add audio track (loop if shorter than video) ──
        guard let audioAssetTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
              let compositionAudioTrack = composition.addMutableTrack(
                  withMediaType: .audio,
                  preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw ExportError.audioMixFailed
        }

        let audioDuration = try await audioAsset.load(.duration)
        var insertTime = CMTime.zero
        let videoSeconds = CMTimeGetSeconds(videoDuration)
        let audioSeconds = CMTimeGetSeconds(audioDuration)

        // Loop audio to fill the full video duration
        while CMTimeGetSeconds(insertTime) < videoSeconds {
            let remaining = CMTimeSubtract(videoDuration, insertTime)
            let insertDuration = CMTimeMinimum(audioDuration, remaining)
            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: insertDuration),
                of: audioAssetTrack,
                at: insertTime
            )
            insertTime = CMTimeAdd(insertTime, insertDuration)
        }

        // ── Audio fade in/out via AVMutableAudioMixInputParameters ──
        let audioParams = AVMutableAudioMixInputParameters(track: compositionAudioTrack)

        // Fade in: 0 → 1 over first 1 second
        let fadeInEnd = CMTimeMakeWithSeconds(AudioConfig.fadeInDuration, preferredTimescale: 600)
        audioParams.setVolumeRamp(fromStartVolume: 0.0, toEndVolume: 1.0,
                                  timeRange: CMTimeRange(start: .zero, duration: fadeInEnd))

        // Fade out: 1 → 0 over last 2 seconds
        let fadeOutStart = CMTimeMakeWithSeconds(videoSeconds - AudioConfig.fadeOutDuration, preferredTimescale: 600)
        let fadeOutDuration = CMTimeMakeWithSeconds(AudioConfig.fadeOutDuration, preferredTimescale: 600)
        audioParams.setVolumeRamp(fromStartVolume: 1.0, toEndVolume: 0.0,
                                  timeRange: CMTimeRange(start: fadeOutStart, duration: fadeOutDuration))

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [audioParams]

        // ── Export the mixed composition ──
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("collage_mixed_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ExportError.audioMixFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.audioMix = audioMix

        await exportSession.export()

        guard exportSession.status == .completed else {
            #if DEBUG
            print("❌ Audio mix failed: \(exportSession.error?.localizedDescription ?? "unknown")")
            #endif
            throw ExportError.audioMixFailed
        }

        return outputURL
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
        case audioMixFailed

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
            case .audioMixFailed:
                return "Failed to mix background music with video."
            }
        }
    }
}
