// CollageView.swift
//
// The collage screen.  Two phases:
//   1. Source picker  – user picks a year (place / person added later).
//   2. Collage display – rendered collage image with an optional Save button.
//
// Follows the same visual language as the rest of the app:
//   - Dark-mode-first colour palette.
//   - SkeletonView for loading states.
//   - Spring animations on state transitions.
//   - Haptic feedback on taps.
//
// No customisation knobs in v1.  The user picks a source, sees the result,
// and optionally saves it.  That's the whole flow.

import SwiftUI
import Photos


struct CollageView: View {

    // MARK: - State & VM

    @StateObject private var viewModel = CollageViewModel()

    /// Whether the user has picked a source and we're showing the collage.
    @State private var selectedSource: CollageSourceType? = nil

    /// Tap the collage to hide / show the Save & Regenerate buttons so the
    /// image can breathe.  Resets to visible every time a new collage loads.
    @State private var buttonsVisible = true

    /// Controls the iOS share sheet for video export
    @State private var showingVideoShareSheet = false

    // MARK: - Body

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                if let source = selectedSource {
                    collageDisplayView(source: source)
                } else {
                    sourcePickerView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(selectedSource.map(\.displayTitle) ?? "Make a Collage")
            .toolbar {
                if selectedSource != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Back") {
                            withAnimation(.easeOut(duration: 0.25)) {
                                selectedSource = nil
                                viewModel.cleanup()
                            }
                        }
                        .opacity(buttonsVisible ? 1 : 0)
                        .animation(.easeInOut(duration: 0.25), value: buttonsVisible)
                    }
                }
            }
        }
        .onAppear {
            viewModel.ensureIndexReady()
            AnalyticsService.shared.logCollageSourceView(source: "picker")
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }

    // MARK: - Source Picker

    private var sourcePickerView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // ── Header ──
                VStack(spacing: 8) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 44))
                        .foregroundColor(.accentColor)
                    Text("Create a Collage")
                        .font(.title.bold())
                    Text("Pick a theme and we'll find your best photos.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.top, 32)

                // ── Year section ──
                if !viewModel.availableYears.isEmpty {
                    pickerSection(
                        title: "By Year",
                        icon: "calendar",
                        items: viewModel.availableYears.map { year in
                            PickerItem(
                                label: "\(year)",
                                source: .year(year)
                            )
                        }
                    )
                }

                // ── Place section  (shown only if data available) ──
                if !viewModel.availablePlaces.isEmpty {
                    pickerSection(
                        title: "By Place",
                        icon: "mappin.and.ellipse",
                        items: viewModel.availablePlaces.map { place in
                            PickerItem(
                                label: place,
                                source: .place(place)
                            )
                        }
                    )
                }

                // ── Person section  (shown only if data available) ──
                if !viewModel.availablePeople.isEmpty {
                    pickerSection(
                        title: "By Person",
                        icon: "person.circle",
                        items: viewModel.availablePeople.map { person in
                            PickerItem(
                                label: person,
                                source: .person(person)
                            )
                        }
                    )
                }

                Spacer()
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - Collage Display

    private func collageDisplayView(source: CollageSourceType) -> some View {
        VStack(spacing: 0) {
            switch viewModel.state {
            case .idle:
                SkeletonView()

            case .loading:
                SkeletonView()

            case .loaded:
                collageLoadedView(source: source)

            case .empty:
                emptyCollageView

            case .error(let message):
                errorCollageView(message: message, source: source)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            buttonsVisible = true
            viewModel.generateCollage(source: source)
            AnalyticsService.shared.logCollageSourceView(source: source.analyticsLabel)
        }
        // Auto-dismiss save message after 2 seconds
        .onChange(of: viewModel.saveMessage) { _, newValue in
            if newValue != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    viewModel.saveMessage = nil
                }
            }
        }
    }

    private func collageLoadedView(source: CollageSourceType) -> some View {
        VStack(spacing: 20) {
            Spacer()

            // ── Rendered collage image ──
            // Tapping anywhere on the image toggles the buttons.
            if let image = viewModel.renderedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
                    .padding(.horizontal, buttonsVisible ? 24 : 0)
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeInOut(duration: 0.25)) {
                            buttonsVisible.toggle()
                        }
                    }
                    .id(image)  // Force SwiftUI to treat each new image as a fresh view
                    .transition(.opacity)
                    .animation(.easeIn(duration: 0.3), value: image)
            }

            // ── Save & Share buttons ──
            HStack(spacing: 16) {
                // Share button
                if let image = viewModel.renderedImage {
                    ShareLink(item: Image(uiImage: image), preview: SharePreview(source.displayTitle, image: Image(uiImage: image))) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(Color.secondary)
                        .cornerRadius(12)
                        .shadow(color: Color.secondary.opacity(0.4), radius: 6, x: 0, y: 3)
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    })
                }

                // Save button
                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    viewModel.saveCollage()
                }) {
                    HStack(spacing: 8) {
                        if viewModel.isSaving {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text(viewModel.isSaving ? "Saving…" : "Save")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .cornerRadius(12)
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 6, x: 0, y: 3)
                }
                .disabled(viewModel.isSaving)
            }
            .opacity(buttonsVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: buttonsVisible)

            // ── Regenerate & Export Video buttons ──
            VStack(spacing: 8) {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.generateCollage(source: source)
                }) {
                    Label("Regenerate", systemImage: "arrow.counterclockwise")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    viewModel.exportVideo()
                }) {
                    Label("Export Video", systemImage: "film")
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                }
                .disabled(viewModel.isExportingVideo)
            }
            .padding(.top, 4)
            .opacity(buttonsVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: buttonsVisible)

            Spacer()
        }
        // ── Video export progress overlay ──
        .overlay {
            if viewModel.isExportingVideo {
                videoExportProgressView
            }
        }
        // ── Auto-show share sheet when video is ready ──
        .onChange(of: viewModel.exportedVideoURL) { _, newURL in
            if let url = newURL {
                showingVideoShareSheet = true
            }
        }
        .sheet(isPresented: $showingVideoShareSheet) {
            if let videoURL = viewModel.exportedVideoURL {
                VideoShareSheet(videoURL: videoURL)
            }
        }
        // ── Toast overlay (always visible — it's a confirmation, not a control) ──
        .overlay(alignment: .bottom) {
            if let msg = viewModel.saveMessage {
                Text(msg)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray))
                    .cornerRadius(20)
                    .padding(.bottom, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeOut(duration: 0.3), value: viewModel.saveMessage != nil)
            }
        }
    }

    private var emptyCollageView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.on.rectangle.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Photos Found")
                .font(.title2.bold())
            Text("There aren't enough photos for this source to make a collage.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private func errorCollageView(message: String, source: CollageSourceType) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)
            Text("Something Went Wrong")
                .font(.title2.bold())
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Try Again") {
                viewModel.generateCollage(source: source)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    // MARK: - Reusable picker section

    private func pickerSection(title: String, icon: String, items: [PickerItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items, id: \.label) { item in
                        pickerChip(item)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func pickerChip(_ item: PickerItem) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeOut(duration: 0.25)) {
                selectedSource = item.source
            }
        }) {
            Text(item.label)
                .font(.body.weight(.medium))
                .foregroundColor(.primary)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color(.systemGray6))
                .cornerRadius(20)
                .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
        }
    }

    // MARK: - Video Export Progress View

    private var videoExportProgressView: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .transition(.opacity)

            // Progress card
            VStack(spacing: 20) {
                // Circular progress indicator
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 8)
                        .frame(width: 100, height: 100)

                    Circle()
                        .trim(from: 0, to: CGFloat(viewModel.videoExportProgress))
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.3), value: viewModel.videoExportProgress)

                    Text("\(Int(viewModel.videoExportProgress * 100))%")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                }

                VStack(spacing: 8) {
                    Text("Exporting Video")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text("Creating Ken Burns effects...")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemGray6).opacity(0.95))
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            )
            .scaleEffect(viewModel.isExportingVideo ? 1.0 : 0.8)
            .opacity(viewModel.isExportingVideo ? 1.0 : 0.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.isExportingVideo)
        }
    }
}


// MARK: - PickerItem

/// Simple value type for source-picker chips.
private struct PickerItem {
    let label:  String
    let source: CollageSourceType
}


// MARK: - Video Share Sheet

/// UIKit wrapper for sharing video files via UIActivityViewController
struct VideoShareSheet: UIViewControllerRepresentable {
    let videoURL: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let activityVC = UIActivityViewController(
            activityItems: [videoURL],
            applicationActivities: nil
        )
        return activityVC
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}
