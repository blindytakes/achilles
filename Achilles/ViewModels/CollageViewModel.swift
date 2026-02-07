// CollageViewModel.swift
//
// Orchestrates the full collage lifecycle: source selection → fetch →
// render → optional save.  Publishes state for CollageView to react to.
//
// Follows the same patterns as PhotoViewModel:
//   - @MainActor for all published-property mutations.
//   - Task-based concurrency with proper cancellation.
//   - Telemetry spans + Firebase Analytics for every meaningful event.
//   - CollageState mirrors the PageState pattern used elsewhere.
//
// Save-to-library
//   The user must tap "Save" explicitly.  When they do, we write the
//   rendered UIImage to PHPhotoLibrary via performChangesAndWait.  This is
//   the only place in the app that writes to the photo library — the
//   .readWrite permission is already granted at auth time.

import SwiftUI
import Photos


@MainActor
class CollageViewModel: ObservableObject {

    // MARK: - Published state

    @Published var state: CollageState = .idle

    /// The rendered collage image, available once state == .loaded.
    @Published var renderedImage: UIImage? = nil

    /// Whether a save is currently in progress (disables the Save button).
    @Published var isSaving = false

    /// Toast / feedback message shown briefly after a save completes.
    @Published var saveMessage: String? = nil

    /// Whether a video export is currently in progress.
    @Published var isExportingVideo = false

    /// Video export progress (0.0 to 1.0).
    @Published var videoExportProgress: Float = 0.0

    /// URL of the exported video (nil until export completes).
    @Published var exportedVideoURL: URL? = nil

    // MARK: - Dependencies

    private let sourceService: CollageSourceServiceProtocol
    private let renderer:      CollageRenderer
    private let videoExporter: CollageVideoExporter

    /// The PhotoIndexService that backs the source service.  We hold a
    /// reference so we can kick off the index build on first use if needed.
    private let indexService: PhotoIndexServiceProtocol

    // MARK: - Task management

    private var activeTask: Task<Void, Never>? = nil

    // MARK: - Init

    init(
        sourceService: CollageSourceServiceProtocol? = nil,
        indexService:  PhotoIndexServiceProtocol?    = nil,
        renderer:      CollageRenderer?              = nil,
        videoExporter: CollageVideoExporter?         = nil
    ) {
        // Wire defaults with shared index so source service and index
        // service are talking to the same instance.
        let idx = indexService ?? PhotoIndexService.shared
        self.indexService  = idx
        self.sourceService = sourceService ?? CollageSourceService(indexService: idx)
        self.renderer      = renderer      ?? CollageRenderer()
        self.videoExporter = videoExporter ?? CollageVideoExporter()
    }

    // MARK: - Public API

    /// Available years / places / people for the source picker.
    var availableYears:  [Int]    { sourceService.availableYears() }
    var availablePlaces: [String] { sourceService.availablePlaces() }
    var availablePeople: [String] { sourceService.availablePeople() }

    /// Kick off index build if it hasn't happened yet.  Call this when the
    /// collage page appears — it's a no-op if the index is already ready.
    func ensureIndexReady() {
        guard !indexService.isIndexReady else { return }
        Task {
            await indexService.buildIndex()
        }
    }

    /// Generate a collage for the given source.  Cancels any in-flight
    /// generation first.
    func generateCollage(source: CollageSourceType) {
        // Cancel previous
        activeTask?.cancel()
        activeTask = nil

        state          = .loading
        renderedImage  = nil

        let task = Task { [weak self] in
            guard let self = self else { return }
            await self.performGeneration(source: source)
        }
        activeTask = task
    }

    /// Save the current rendered collage to the photo library.
    func saveCollage() {
        guard let image = renderedImage else { return }
        guard case .loaded(let collage) = state else { return }

        isSaving = true

        Task { [weak self] in
            guard let self = self else { return }
            await self.performSave(image: image, source: collage.source)
        }
    }

    /// Export the current collage as a Ken Burns video.
    func exportVideo() {
        guard case .loaded(let collage) = state else { return }

        isExportingVideo = true
        videoExportProgress = 0.0
        exportedVideoURL = nil

        Task { [weak self] in
            guard let self = self else { return }
            await self.performVideoExport(collage: collage)
        }
    }

    // MARK: - Private – Generation

    private func performGeneration(source: CollageSourceType) async {
        let spanStart = Date()

        // 1. Resolve source → MediaItems via the source service
        guard let collage = await sourceService.resolve(source: source) else {
            // No photos matched
            await MainActor.run { self.state = .empty }
            TelemetryService.shared.log(
                "collage generation: empty result",
                attributes: ["source_type": source.analyticsLabel]
            )
            return
        }

        guard !Task.isCancelled else { return }

        // 2. Render
        guard let image = await renderer.render(items: collage.items) else {
            await MainActor.run {
                self.state = .error(message: "Failed to render collage. Please try again.")
            }
            TelemetryService.shared.log(
                "collage generation: render failed",
                severity: .error,
                attributes: ["source_type": source.analyticsLabel]
            )
            return
        }

        guard !Task.isCancelled else { return }

        // 3. Publish success
        let durationMs = Int(Date().timeIntervalSince(spanStart) * 1000)

        await MainActor.run {
            self.renderedImage = image
            self.state         = .loaded(collage)
        }

        // 4. Telemetry + Analytics
        TelemetryService.shared.recordSpan(
            name: "collage.generate",
            startTime: spanStart,
            durationMs: durationMs,
            attributes: [
                "source_type": source.analyticsLabel,
                "photo_count": collage.items.count
            ]
        )
        TelemetryService.shared.recordHistogram(
            name: "throwbaks.collage.generateDuration",
            value: Double(durationMs),
            attributes: ["source_type": source.analyticsLabel]
        )
        TelemetryService.shared.incrementCounter(
            name: "throwbaks.collage.generated",
            attributes: ["source_type": source.analyticsLabel]
        )
        TelemetryService.shared.log(
            "collage generated",
            attributes: [
                "source_type": source.analyticsLabel,
                "photo_count": collage.items.count,
                "duration_ms": durationMs
            ]
        )
        AnalyticsService.shared.logCollageGenerated(
            source: source.analyticsLabel,
            photoCount: collage.items.count,
            durationMs: durationMs
        )
    }

    // MARK: - Private – Save

    private func performSave(image: UIImage, source: CollageSourceType) async {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let creationRequest = PHAssetCreationRequest.creationRequestForAsset(from: image)
                _ = creationRequest   // asset is added to the library automatically
            }

            await MainActor.run {
                self.isSaving   = false
                self.saveMessage = "Collage saved to your Photos!"
            }

            // Telemetry + Analytics
            TelemetryService.shared.incrementCounter(
                name: "throwbaks.collage.saved",
                attributes: ["source_type": source.analyticsLabel]
            )
            TelemetryService.shared.log(
                "collage saved to photo library",
                attributes: ["source_type": source.analyticsLabel]
            )
            AnalyticsService.shared.logCollageSaved(source: source.analyticsLabel)

            #if DEBUG
            print("✅ CollageViewModel: collage saved to photo library.")
            #endif

        } catch {
            await MainActor.run {
                self.isSaving   = false
                self.saveMessage = "Save failed. Please try again."
            }
            #if DEBUG
            print("❌ CollageViewModel: save failed – \(error.localizedDescription)")
            #endif
            TelemetryService.shared.log(
                "collage save failed",
                severity: .error,
                attributes: ["source_type": source.analyticsLabel, "error": error.localizedDescription]
            )
        }
    }

    // MARK: - Private – Video Export

    private func performVideoExport(collage: MemoryCollage) async {
        let spanStart = Date()

        do {
            // Export video with progress updates
            let videoURL = try await videoExporter.export(collage: collage) { [weak self] progress in
                Task { @MainActor in
                    self?.videoExportProgress = progress
                }
            }

            let durationMs = Int(Date().timeIntervalSince(spanStart) * 1000)

            await MainActor.run {
                self.isExportingVideo = false
                self.exportedVideoURL = videoURL
                self.videoExportProgress = 1.0
            }

            // Telemetry + Analytics
            TelemetryService.shared.recordSpan(
                name: "collage.videoExport",
                startTime: spanStart,
                durationMs: durationMs,
                attributes: [
                    "source_type": collage.source.analyticsLabel,
                    "photo_count": collage.items.count
                ]
            )
            TelemetryService.shared.incrementCounter(
                name: "throwbaks.collage.videoExported",
                attributes: ["source_type": collage.source.analyticsLabel]
            )
            TelemetryService.shared.log(
                "collage video exported",
                attributes: [
                    "source_type": collage.source.analyticsLabel,
                    "photo_count": collage.items.count,
                    "duration_ms": durationMs
                ]
            )

            #if DEBUG
            print("✅ CollageViewModel: video exported → \(videoURL.path)")
            #endif

        } catch {
            await MainActor.run {
                self.isExportingVideo = false
                self.videoExportProgress = 0.0
                self.saveMessage = "Video export failed. Please try again."
            }

            #if DEBUG
            print("❌ CollageViewModel: video export failed – \(error.localizedDescription)")
            #endif

            TelemetryService.shared.log(
                "collage video export failed",
                severity: .error,
                attributes: [
                    "source_type": collage.source.analyticsLabel,
                    "error": error.localizedDescription
                ]
            )
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        activeTask?.cancel()
        activeTask     = nil
        renderedImage  = nil
        exportedVideoURL = nil
        state          = .idle
    }

    deinit {
        activeTask?.cancel()
    }
}
