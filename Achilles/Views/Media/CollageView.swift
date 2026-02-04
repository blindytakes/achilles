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
            .navigationTitle(selectedSource != nil ? selectedSource!.displayTitle : "Make a Collage")
            .toolbar {
                if selectedSource != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Back") {
                            withAnimation(.easeOut(duration: 0.25)) {
                                selectedSource = nil
                                viewModel.cleanup()
                            }
                        }
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
            if let image = viewModel.renderedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
                    .padding(.horizontal, 24)
            }

            // ── Save button ──
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
                    Text(viewModel.isSaving ? "Saving…" : "Save to Photos")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(Color.accentColor)
                .cornerRadius(12)
                .shadow(color: Color.accentColor.opacity(0.4), radius: 6, x: 0, y: 3)
            }
            .disabled(viewModel.isSaving)

            // ── Regenerate button ──
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.generateCollage(source: source)
            }) {
                Label("Regenerate", systemImage: "arrow.counterclockwise")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)

            Spacer()
        }
        // ── Toast overlay ──
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
}


// MARK: - PickerItem

/// Simple value type for source-picker chips.
private struct PickerItem {
    let label:  String
    let source: CollageSourceType
}
