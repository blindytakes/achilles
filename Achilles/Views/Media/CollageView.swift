// CollageView.swift
//
// The collage screen.  Two phases:
//   1. Source picker  – user picks a year, place, or person.
//   2. Collage display – rendered collage with layout picker, Save, Share,
//      and Export Video buttons.
//
// Visual personality:
//   - Warm gradient backgrounds matching the brand greens.
//   - Staggered spring entrance animations on chips.
//   - Bouncy collage reveal with scale + opacity.
//   - Gradient-filled action buttons with glow shadows.
//   - Animated progress ring with rotating subtitle hints.
//   - Playful success toast with green accent.

import SwiftUI
import Photos


// MARK: - Brand Palette (shared with LoginSignupView)

private struct Palette {
    static let darkGreen  = Color(red: 0.13, green: 0.55, blue: 0.13)
    static let medGreen   = Color(red: 0.30, green: 0.70, blue: 0.30)
    static let lightGreen = Color(red: 0.40, green: 0.80, blue: 0.40)
    static let mintGreen  = Color(red: 0.55, green: 0.90, blue: 0.55)

    /// Primary action gradient (Save, Export).
    static let primaryGradient = LinearGradient(
        colors: [medGreen, darkGreen],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Secondary action gradient (Share).
    static let secondaryGradient = LinearGradient(
        colors: [Color(.systemGray4), Color(.systemGray3)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Subtle background gradient for the source picker.
    static let pickerBackground = LinearGradient(
        colors: [
            lightGreen.opacity(0.12),
            medGreen.opacity(0.06),
            Color(.systemBackground)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Chip gradient when selected.
    static let chipGradient = LinearGradient(
        colors: [lightGreen, darkGreen],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}


struct CollageView: View {

    // MARK: - State & VM

    @StateObject private var viewModel = CollageViewModel()

    /// Whether the user has picked a source and we're showing the collage.
    @State private var selectedSource: CollageSourceType? = nil

    /// Tap the collage to hide / show controls so the image can breathe.
    @State private var buttonsVisible = true

    /// Controls the iOS share sheet for video export.
    @State private var showingVideoShareSheet = false

    /// Drives staggered entrance of picker chips.
    @State private var pickerAppeared = false

    /// Drives collage reveal animation.
    @State private var collageRevealed = false

    /// Which tab is active in the source picker.
    @State private var activeTab: PickerTab = .years

    /// Scroll-position ID for each wheel (the index currently at centre).
    /// These are the single source of truth — text styling AND scroll
    /// position both read from these.
    @State private var focusedYearIndex: Int? = 0
    @State private var focusedPlaceIndex: Int? = 0
    @State private var focusedPersonIndex: Int? = 0

    // MARK: - Body

    var body: some View {
        NavigationView {
            ZStack {
                // Background that shifts between picker gradient and display
                if selectedSource == nil {
                    Palette.pickerBackground.ignoresSafeArea()
                        .transition(.opacity)
                } else {
                    Color(.systemBackground).ignoresSafeArea()
                        .transition(.opacity)
                }

                if let source = selectedSource {
                    collageDisplayView(source: source)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                } else {
                    sourcePickerView
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: selectedSource != nil)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(selectedSource.map(\.displayTitle) ?? "Make a Collage")
            .toolbar {
                if selectedSource != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                selectedSource = nil
                                viewModel.cleanup()
                                collageRevealed = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.body.weight(.semibold))
                                Text("Back")
                            }
                            .foregroundColor(Palette.darkGreen)
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
            // Trigger staggered entrance after a tiny delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) {
                    pickerAppeared = true
                }
            }
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Source Picker
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var sourcePickerView: some View {
        VStack(spacing: 0) {
            // ── Header ──
            VStack(spacing: 10) {
                ZStack {
                    Text("🎞️")
                        .font(.system(size: 38))
                        .rotationEffect(.degrees(-10))
                        .offset(x: -26, y: 4)
                    Text("📸")
                        .font(.system(size: 46))
                    Text("✨")
                        .font(.system(size: 26))
                        .offset(x: 28, y: -16)
                }
                .scaleEffect(pickerAppeared ? 1.0 : 0.3)
                .opacity(pickerAppeared ? 1.0 : 0.0)

                Text("Create a Collage")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.primary)
                    .opacity(pickerAppeared ? 1.0 : 0.0)
                    .offset(y: pickerAppeared ? 0 : 12)

                Text("Pick a vibe and we'll find your best shots")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .opacity(pickerAppeared ? 1.0 : 0.0)
                    .offset(y: pickerAppeared ? 0 : 8)
            }
            .padding(.top, 16)
            .padding(.bottom, 16)

            // ── Segmented tab bar ──
            segmentedTabBar
                .padding(.horizontal, 40)
                .opacity(pickerAppeared ? 1.0 : 0.0)
                .animation(
                    .spring(response: 0.6, dampingFraction: 0.75).delay(0.06),
                    value: pickerAppeared
                )

            // ── Wheel for active tab ──
            wheelForActiveTab
                .padding(.top, 20)
                .scaleEffect(pickerAppeared ? 1.0 : 0.85)
                .opacity(pickerAppeared ? 1.0 : 0.0)
                .animation(
                    .spring(response: 0.6, dampingFraction: 0.75).delay(0.1),
                    value: pickerAppeared
                )

            // ── "Go" button ──
            goButton
                .padding(.top, 20)
                .opacity(pickerAppeared ? 1.0 : 0.0)
                .animation(
                    .spring(response: 0.6, dampingFraction: 0.75).delay(0.15),
                    value: pickerAppeared
                )

            Spacer()
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Collage Display
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func collageDisplayView(source: CollageSourceType) -> some View {
        VStack(spacing: 0) {
            switch viewModel.state {
            case .idle, .loading:
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
            collageRevealed = false
            viewModel.generateCollage(source: source)
            AnalyticsService.shared.logCollageSourceView(source: source.analyticsLabel)
        }
        .onChange(of: viewModel.saveMessage) { _, newValue in
            if newValue != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        viewModel.saveMessage = nil
                    }
                }
            }
        }
        // Trigger reveal animation when image arrives
        .onChange(of: viewModel.renderedImage != nil) { _, hasImage in
            if hasImage {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    collageRevealed = true
                }
            }
        }
    }

    private func collageLoadedView(source: CollageSourceType) -> some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    // ── Rendered collage image ──
                    if let image = viewModel.renderedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: Palette.darkGreen.opacity(0.18), radius: 16, x: 0, y: 8)
                            .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
                            .padding(.horizontal, buttonsVisible ? 20 : 4)
                            .scaleEffect(collageRevealed ? 1.0 : 0.88)
                            .opacity(collageRevealed ? 1.0 : 0.0)
                            .onTapGesture {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    buttonsVisible.toggle()
                                }
                            }
                            .id(image)
                    } else {
                        ProgressView()
                            .scaleEffect(1.2)
                            .frame(maxWidth: .infinity, minHeight: 300)
                    }

                    // ── Layout picker ──
                    layoutPicker
                        .offset(y: buttonsVisible ? 0 : 20)
                        .opacity(buttonsVisible ? 1 : 0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: buttonsVisible)

                    // ── Action buttons ──
                    actionButtons(source: source)
                        .offset(y: buttonsVisible ? 0 : 20)
                        .opacity(buttonsVisible ? 1 : 0)
                        .animation(.spring(response: 0.45, dampingFraction: 0.75).delay(0.03), value: buttonsVisible)

                    // ── Regenerate ──
                    regenerateButton(source: source)
                        .offset(y: buttonsVisible ? 0 : 12)
                        .opacity(buttonsVisible ? 1 : 0)
                        .animation(.spring(response: 0.45, dampingFraction: 0.75).delay(0.06), value: buttonsVisible)

                    // ── Music + Export ──
                    musicAndExportSection
                        .offset(y: buttonsVisible ? 0 : 12)
                        .opacity(buttonsVisible ? 1 : 0)
                        .animation(.spring(response: 0.45, dampingFraction: 0.75).delay(0.09), value: buttonsVisible)
                }
                .padding(.vertical, 8)
                // Center the content group vertically when it's shorter than the screen
                .frame(minHeight: geo.size.height)
            }
        }
        // ── Video export overlay ──
        .overlay {
            if viewModel.isExportingVideo {
                videoExportProgressView
                    .transition(.opacity)
            } else if let videoURL = viewModel.exportedVideoURL {
                VideoPreviewView(
                    videoURL: videoURL,
                    onSaveToPhotos: { viewModel.saveVideoToPhotos() },
                    onShare: { showingVideoShareSheet = true },
                    onRegenerate: {
                        viewModel.dismissVideoPreview()
                        viewModel.exportVideo()
                    },
                    onDismiss: { viewModel.dismissVideoPreview() },
                    isSaving: viewModel.isSavingVideo
                )
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.isExportingVideo)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.exportedVideoURL != nil)
        .sheet(isPresented: $showingVideoShareSheet) {
            if let videoURL = viewModel.exportedVideoURL {
                VideoShareSheet(videoURL: videoURL)
            }
        }
        // ── Success toast ──
        .overlay(alignment: .bottom) {
            if let msg = viewModel.saveMessage {
                successToast(msg)
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Sub-views (Display Phase)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var layoutPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CollageLayout.allCases.filter { $0 != .filmStrip }, id: \.self) { layout in
                    layoutChip(layout)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func actionButtons(source: CollageSourceType) -> some View {
        HStack(spacing: 14) {
            // Share button
            if let image = viewModel.renderedImage {
                ShareLink(
                    item: Image(uiImage: image),
                    preview: SharePreview(source.displayTitle, image: Image(uiImage: image))
                ) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 13)
                    .background(Palette.secondaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                })
            }

            // Save button
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                viewModel.saveCollage()
            } label: {
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
                .padding(.horizontal, 24)
                .padding(.vertical, 13)
                .background(Palette.primaryGradient)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Palette.darkGreen.opacity(0.35), radius: 8, x: 0, y: 4)
            }
            .disabled(viewModel.isSaving)
        }
    }

    private func regenerateButton(source: CollageSourceType) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            collageRevealed = false
            viewModel.generateCollage(source: source)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.subheadline.weight(.medium))
                    .rotationEffect(.degrees(collageRevealed ? 0 : -180))
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: collageRevealed)
                Text("Shuffle Photos")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundColor(Palette.darkGreen)
        }
        .padding(.top, 2)
    }

    private var musicAndExportSection: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            // Cycle between the two music tracks on each export
            let tracks = MusicTrack.musicTracks
            if let currentIdx = tracks.firstIndex(of: viewModel.selectedMusicTrack) {
                viewModel.selectedMusicTrack = tracks[(currentIdx + 1) % tracks.count]
            } else {
                viewModel.selectedMusicTrack = tracks.first ?? .atmospheric
            }
            viewModel.exportVideo()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "film")
                    .font(.subheadline.weight(.semibold))
                Text("Export Video")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(Palette.darkGreen)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .strokeBorder(Palette.darkGreen.opacity(0.35), lineWidth: 1.5)
            )
        }
        .disabled(viewModel.isExportingVideo)
        .padding(.top, 2)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Empty & Error States
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var emptyCollageView: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("📭")
                .font(.system(size: 56))
            Text("No Photos Found")
                .font(.title2.bold())
        }
    }

    private func errorCollageView(message: String, source: CollageSourceType) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Text("😵")
                .font(.system(size: 56))
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
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(Palette.primaryGradient)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Spacer()
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Segmented Tab Bar
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// All three tabs are always visible; empty ones show a helpful message.
    private var availableTabs: [PickerTab] {
        [.years, .places, .people]
    }

    private var segmentedTabBar: some View {
        HStack(spacing: 0) {
            ForEach(availableTabs, id: \.self) { tab in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        activeTab = tab
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: .medium))
                        Text(tab.label)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundColor(activeTab == tab ? .white : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        Group {
                            if activeTab == tab {
                                Palette.chipGradient
                            } else {
                                Color.clear
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemGray6))
        )
        .onAppear {
            // Default to the first available tab
            if let first = availableTabs.first {
                activeTab = first
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Scroll Wheel (Generic)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Height of one row in the scroll wheel.
    private let wheelRowHeight: CGFloat = 52
    /// Visible rows (odd so center is focused).
    private let visibleWheelRows: Int = 5

    /// The items for the current active tab.
    private var activeWheelItems: [String] {
        switch activeTab {
        case .years:  return viewModel.availableYears.map { "\($0)" }
        case .places: return viewModel.availablePlaces
        case .people: return viewModel.availablePeople
        }
    }

    /// Binding to the scroll-position ID for the active tab.
    private var activeFocusedIndex: Binding<Int?> {
        switch activeTab {
        case .years:  return $focusedYearIndex
        case .places: return $focusedPlaceIndex
        case .people: return $focusedPersonIndex
        }
    }

    /// The resolved (non-nil) focused index for the active tab.
    private var resolvedFocusedIndex: Int {
        activeFocusedIndex.wrappedValue ?? 0
    }

    /// The accent color for the active tab.
    private var activeAccentColor: Color {
        switch activeTab {
        case .years:  return Palette.darkGreen
        case .places: return Color(red: 0.2, green: 0.6, blue: 0.85)
        case .people: return Color(red: 0.85, green: 0.45, blue: 0.55)
        }
    }

    /// Empty-state info per tab.
    private var emptyWheelMessage: (emoji: String, title: String, subtitle: String) {
        switch activeTab {
        case .years:
            return ("📅", "No Years Found", "Photos are still loading…")
        case .places:
            return ("📍", "No Places Found", "Photos need location data to appear here")
        case .people:
            return ("👤", "No People Found", "Open the People album in Photos first")
        }
    }

    @ViewBuilder
    private var wheelForActiveTab: some View {
        let items = activeWheelItems
        if items.isEmpty {
            VStack(spacing: 10) {
                Text(emptyWheelMessage.emoji)
                    .font(.system(size: 36))
                Text(emptyWheelMessage.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(emptyWheelMessage.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .frame(height: wheelRowHeight * CGFloat(visibleWheelRows))
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        } else {
            scrollWheel(
                items: items,
                focusedIndex: activeFocusedIndex,
                accentColor: activeAccentColor
            )
            .id(activeTab) // Force fresh wheel when tab changes
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: activeTab)
        }
    }

    /// Coordinate space name for the scroll wheel so rows can measure
    /// their position relative to the wheel's visible frame.
    private static let wheelCoordinateSpace = "wheelCoord"

    private func scrollWheel(
        items: [String],
        focusedIndex: Binding<Int?>,
        accentColor: Color
    ) -> some View {
        let wheelHeight = wheelRowHeight * CGFloat(visibleWheelRows)
        let topPadding  = wheelRowHeight * CGFloat(visibleWheelRows / 2)
        let centerY     = wheelHeight / 2  // vertical midpoint of the wheel

        return ZStack {
            // ── Fixed highlight pill, always dead-centre ──
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accentColor.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(accentColor.opacity(0.25), lineWidth: 1)
                )
                .frame(height: wheelRowHeight)
                .allowsHitTesting(false)

            // ── Scrollable items that move through the centre ──
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    // Top spacer so first item can sit in the centre
                    Color.clear.frame(height: topPadding)

                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        wheelRow(
                            index: index,
                            item: item,
                            centerY: centerY,
                            accentColor: accentColor,
                            focusedIndex: focusedIndex
                        )
                        .id(index)
                    }

                    // Bottom spacer so last item can sit in the centre
                    Color.clear.frame(height: topPadding)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: focusedIndex)
            .onChange(of: focusedIndex.wrappedValue) { _, _ in
                UISelectionFeedbackGenerator().selectionChanged()
            }
            // Fade top and bottom edges
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: wheelRowHeight * 1.2)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: wheelRowHeight * 1.2)
                }
            )
        }
        .coordinateSpace(name: Self.wheelCoordinateSpace)
        .frame(height: wheelHeight)
        .padding(.horizontal, 40)
    }

    /// A single row in the scroll wheel.  Uses GeometryReader to measure its
    /// vertical position inside the wheel and styles itself as "focused" when
    /// it's physically near the centre — no reliance on the binding value.
    private func wheelRow(
        index: Int,
        item: String,
        centerY: CGFloat,
        accentColor: Color,
        focusedIndex: Binding<Int?>
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                focusedIndex.wrappedValue = index
            }
        } label: {
            GeometryReader { geo in
                let rowMidY  = geo.frame(in: .named(Self.wheelCoordinateSpace)).midY
                let distance = abs(rowMidY - centerY)
                let isFocused = distance < (wheelRowHeight * 0.6)

                Text(item)
                    .font(.system(
                        size: isFocused ? 28 : 17,
                        weight: isFocused ? .bold : .medium
                    ))
                    .foregroundColor(isFocused ? accentColor : .secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.easeOut(duration: 0.15), value: isFocused)
            }
        }
        .buttonStyle(.plain)
        .frame(height: wheelRowHeight)
        .contentShape(Rectangle())
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Go Button
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// The CollageSourceType for the current wheel selection.
    private var activeSource: CollageSourceType? {
        let items = activeWheelItems
        guard !items.isEmpty else { return nil }
        let idx = min(resolvedFocusedIndex, items.count - 1)
        switch activeTab {
        case .years:
            return .year(viewModel.availableYears[idx])
        case .places:
            return .place(viewModel.availablePlaces[idx])
        case .people:
            return .person(viewModel.availablePeople[idx])
        }
    }

    /// Human-readable label for the go button.
    private var goButtonLabel: String {
        let items = activeWheelItems
        guard !items.isEmpty else { return "Create Collage" }
        let idx = min(resolvedFocusedIndex, items.count - 1)
        return "Create \(items[idx]) Collage"
    }

    private var goButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if let source = activeSource {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    selectedSource = source
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(goButtonLabel)
                    .font(.headline.weight(.bold))
                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 13)
            .background(Palette.primaryGradient)
            .clipShape(Capsule())
            .shadow(color: Palette.darkGreen.opacity(0.35), radius: 8, x: 0, y: 4)
        }
        .disabled(activeSource == nil)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: goButtonLabel)
    }

    // MARK: - Layout Chip

    private func layoutChip(_ layout: CollageLayout) -> some View {
        let isSelected = viewModel.selectedLayout == layout
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            viewModel.switchLayout(to: layout)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: layout.iconName)
                    .font(.subheadline)
                Text(layout.displayName)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Group {
                    if isSelected {
                        Palette.chipGradient
                    } else {
                        LinearGradient(
                            colors: [Color(.systemGray6), Color(.systemGray6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(
                color: isSelected ? Palette.darkGreen.opacity(0.25) : .black.opacity(0.06),
                radius: isSelected ? 6 : 2,
                x: 0,
                y: isSelected ? 3 : 1
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Toast
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func successToast(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.white)
                .font(.body.weight(.semibold))
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Palette.primaryGradient)
                .shadow(color: Palette.darkGreen.opacity(0.3), radius: 8, x: 0, y: 4)
        )
        .padding(.bottom, 40)
        .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.85)))
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.saveMessage != nil)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Video Export Progress
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Rotating subtitle hints shown during export.
    private var exportSubtitle: String {
        let p = viewModel.videoExportProgress
        if p < 0.25      { return "Loading your best photos…" }
        else if p < 0.55 { return "Adding smooth pan & zoom…" }
        else if p < 0.80 { return "Blending transitions…" }
        else if p < 0.95 { return "Mixing background music…" }
        else             { return "Almost there…" }
    }

    private var videoExportProgressView: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .transition(.opacity)

            // Progress card
            VStack(spacing: 24) {
                // Gradient ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 8)
                        .frame(width: 100, height: 100)

                    Circle()
                        .trim(from: 0, to: CGFloat(viewModel.videoExportProgress))
                        .stroke(
                            AngularGradient(
                                colors: [Palette.lightGreen, Palette.darkGreen, Palette.lightGreen],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.4), value: viewModel.videoExportProgress)

                    Text("\(Int(viewModel.videoExportProgress * 100))%")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                        .animation(.easeInOut, value: viewModel.videoExportProgress)
                }

                VStack(spacing: 8) {
                    Text("Exporting Video")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text(exportSubtitle)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .animation(.easeInOut(duration: 0.3), value: exportSubtitle)
                        .id(exportSubtitle) // Force transition
                        .transition(.push(from: .bottom).combined(with: .opacity))
                }
            }
            .padding(36)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            )
            .scaleEffect(viewModel.isExportingVideo ? 1.0 : 0.8)
            .opacity(viewModel.isExportingVideo ? 1.0 : 0.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.isExportingVideo)
        }
    }
}


// MARK: - Bounce Button Style

/// Gives picker chips a subtle press-down bounce.
private struct BounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}


// MARK: - PickerTab

/// The three categories in the segmented source picker.
private enum PickerTab: Hashable {
    case years, places, people

    var label: String {
        switch self {
        case .years:  return "Years"
        case .places: return "Places"
        case .people: return "People"
        }
    }

    var icon: String {
        switch self {
        case .years:  return "calendar"
        case .places: return "mappin.and.ellipse"
        case .people: return "person.2.fill"
        }
    }
}


// MARK: - Video Share Sheet

/// UIKit wrapper for sharing video files via UIActivityViewController
struct VideoShareSheet: UIViewControllerRepresentable {
    let videoURL: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: [videoURL],
            applicationActivities: nil
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
