// YearCarouselView.swift
//
// A visually engaging year selection carousel shown on cold app launch.
// Displays available memory years as stacked-depth cards with a lightning
// glow border effect. Users scroll horizontally and tap a card to enter
// that year's full content view.

import SwiftUI
import Photos

// MARK: - Year Carousel View

struct YearCarouselView: View {
    @Binding var selectedYear: Int?
    let onDismiss: () -> Void

    @EnvironmentObject var viewModel: PhotoViewModel
    @EnvironmentObject var authVM: AuthViewModel

    // Carousel state
    @State private var hasAppeared = false
    @State private var lastCenteredYear: Int? = nil

    private static let carouselCoordinateSpace = "carouselCoord"

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.08, green: 0.18, blue: 0.10),
                        Color.black
                    ]),
                    center: UnitPoint(x: 0.5, y: 0.55),
                    startRadius: 80,
                    endRadius: 550
                )
                .ignoresSafeArea()

                if viewModel.initialYearScanComplete {
                    if viewModel.availableYearsAgo.isEmpty {
                        emptyStateView
                    } else {
                        carouselContent(in: geometry)
                    }
                } else {
                    scanningView
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if viewModel.initialYearScanComplete {
                viewModel.loadFeaturedImagesForCarousel(years: viewModel.availableYearsAgo)
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                hasAppeared = true
            }
        }
        .onReceive(viewModel.$initialYearScanComplete) { complete in
            if complete {
                viewModel.loadFeaturedImagesForCarousel(years: viewModel.availableYearsAgo)
            }
        }
        .onReceive(viewModel.$availableYearsAgo) { years in
            if viewModel.initialYearScanComplete {
                viewModel.loadFeaturedImagesForCarousel(years: years)
            }
        }
    }

    // MARK: - Carousel Content

    private func carouselContent(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(maxHeight: 30)

            Text("ThrowBaks")
                .font(.system(size: 42, weight: .bold))
                .italic()
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : -20)

            Spacer().frame(height: 28)

            horizontalCarousel(in: geometry)

            Spacer()

            Text("Tap a card to explore")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
                .opacity(hasAppeared ? 1 : 0)
                .padding(.bottom, 40)
        }
        .padding(.top, 50)
        .padding(.bottom, 20)
    }

    // MARK: - Horizontal Carousel

    private func horizontalCarousel(in outerGeo: GeometryProxy) -> some View {
        let cardWidth: CGFloat = outerGeo.size.width * 0.73
        let cardHeight: CGFloat = outerGeo.size.height * 0.67
        let centerX: CGFloat = outerGeo.size.width / 2
        let sortedYears = viewModel.availableYearsAgo.sorted()
        // Use pageStateByYear as a reactivity trigger so cards re-render when images load
        let _ = viewModel.pageStateByYear

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(sortedYears, id: \.self) { yearsAgo in
                    GeometryReader { cardGeo in
                        let cardMidX = cardGeo.frame(in: .named(Self.carouselCoordinateSpace)).midX
                        let distance = abs(cardMidX - centerX)
                        let maxDistance = outerGeo.size.width * 0.6
                        let rawProgress = max(0, 1 - distance / maxDistance)
                        let progress = pow(rawProgress, 1.2)

                        let cardScale = 0.88 + (1.0 - 0.88) * progress
                        let cardOpacity = 0.85 + (1.0 - 0.85) * progress
                        let yRotation = (1.0 - progress) * 10 * (cardMidX < centerX ? 1 : -1)

                        YearCarouselCard(
                            yearsAgo: yearsAgo,
                            cardWidth: cardWidth,
                            cardHeight: cardHeight,
                            viewModel: viewModel
                        )
                        .scaleEffect(cardScale)
                        .opacity(cardOpacity)
                        .rotation3DEffect(
                            .degrees(Double(yRotation)),
                            axis: (x: 0, y: 1, z: 0),
                            perspective: 0.5
                        )
                        .shadow(
                            color: .black.opacity(0.3 * Double(progress)),
                            radius: 20 * progress,
                            x: 0, y: 10 * progress
                        )
                        .onTapGesture {
                            guard progress > 0.7 else { return }
                            handleCardTap(yearsAgo: yearsAgo)
                        }
                        .onChange(of: distance < cardWidth * 0.3) { _, isCentered in
                            if isCentered && lastCenteredYear != yearsAgo {
                                lastCenteredYear = yearsAgo
                                UISelectionFeedbackGenerator().selectionChanged()
                            }
                        }
                    }
                    .frame(width: cardWidth, height: cardHeight)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, (outerGeo.size.width - cardWidth) / 2)
        }
        .scrollTargetBehavior(.viewAligned)
        .coordinateSpace(name: Self.carouselCoordinateSpace)
        .frame(height: cardHeight)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.availableYearsAgo)
    }

    // MARK: - Card Tap & Transition

    private func handleCardTap(yearsAgo: Int) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        AnalyticsService.shared.logCarouselYearSelected(yearsAgo: yearsAgo)
        selectedYear = yearsAgo
        onDismiss()
    }

    // MARK: - Empty & Loading States

    private var scanningView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.2)
            Text("Finding your memories...")
                .font(.headline)
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Text("No Memories Found")
                .font(.title2.bold())
                .foregroundColor(.white)
            Text("No photos from today's date in previous years")
                .font(.body)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Button("Continue") {
                selectedYear = nil
                onDismiss()
            }
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 8)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Helpers

    static func dateLabel(for yearsAgo: Int) -> String {
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month, .day], from: Date())
        comps.year = (comps.year ?? 0) - yearsAgo
        guard let past = calendar.date(from: comps) else { return "" }
        return past.monthDayWithOrdinalAndYear()
    }
}

// MARK: - Hero card image modifier

private struct HeroCardImageModifier: ViewModifier {
    let yearsAgo: Int
    @Environment(\.heroNamespace) private var heroNamespace
    @Environment(\.heroYear) private var heroYear
    @Environment(\.showCarousel) private var showCarousel

    func body(content: Content) -> some View {
        if let ns = heroNamespace, heroYear == yearsAgo {
            content.matchedGeometryEffect(
                id: "hero-featured-\(yearsAgo)",
                in: ns,
                isSource: showCarousel
            )
        } else {
            content
        }
    }
}

// MARK: - Year Carousel Card

struct YearCarouselCard: View {
    let yearsAgo: Int
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    @ObservedObject var viewModel: PhotoViewModel

    // Card image state — falls back to self-loading if preloaded image isn't ready
    @State private var cardImage: UIImage? = nil

    // Glow animation states
    @State private var glowBreath: Double = 0.4

    private var yearLabel: String {
        yearsAgo == 1 ? "1 Year Ago" : "\(yearsAgo) Years Ago"
    }

    private var dateLabel: String {
        YearCarouselView.dateLabel(for: yearsAgo)
    }

    /// The best available image: preloaded cache first, then self-loaded fallback
    private var displayImage: UIImage? {
        viewModel.getPreloadedFeaturedImage(for: yearsAgo) ?? cardImage
    }

    var body: some View {
        ZStack {
            // Background image
            if let image = displayImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: cardWidth, height: cardHeight)
                    .clipped()
                    .modifier(HeroCardImageModifier(yearsAgo: yearsAgo))
            } else {
                Rectangle()
                    .fill(Color(.systemGray6))
                    .frame(width: cardWidth, height: cardHeight)
                    .shimmering()
            }

            // Gradient overlay
            LinearGradient(
                gradient: Gradient(colors: [
                    .clear,
                    .clear,
                    .black.opacity(0.4),
                    .black.opacity(0.85)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )

            // Text overlay
            VStack(spacing: 8) {
                Spacer()

                Text(yearLabel)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.7), radius: 4, x: 0, y: 2)
                    .shadow(color: .white.opacity(0.3), radius: 2, x: 0, y: 0)
                    .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 0)

                Text(dateLabel)
                    .font(.custom("SnellRoundhand-Bold", size: 26))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(1.0), radius: 2, x: 0, y: 0)
                    .shadow(color: .black.opacity(0.65), radius: 6, x: 0, y: 2)
                    .shadow(color: .white.opacity(0.3), radius: 1.8, x: 0, y: 0)

                Spacer().frame(height: 28)
            }
            .padding(.horizontal, 16)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(lightningGlowBorder)
        .accessibilityLabel("\(yearLabel), \(dateLabel)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Tap to explore memories")
        .onAppear {
            startGlowAnimations()
        }
        // When the page state changes to .loaded, try to grab the featured image
        .onChange(of: viewModel.pageStateByYear[yearsAgo]?.isLoaded) { _, isLoaded in
            if isLoaded == true, displayImage == nil {
                loadFeaturedImageFallback()
            }
        }
        .task {
            // Give the preload pipeline a brief window to deliver, then self-load
            // if it hasn't. With the opportunistic carousel path a prefetch hit
            // typically lands in ~50–300ms, so 250ms is a comfortable upper bound
            // before we fall back — and if the fallback does fire, it uses the
            // same opportunistic path so it snaps in quickly too.
            try? await Task.sleep(nanoseconds: 250_000_000)
            if displayImage == nil {
                loadFeaturedImageFallback()
            }
        }
    }

    /// Fallback: request the featured image via PHImageManager with opportunistic delivery.
    /// PhotoKit fires the completion twice — first with a low-res "proxy" (~20–50ms),
    /// then with the sharp image. This produces a visible snap from blurry to sharp
    /// instead of staring at a shimmer for 1s+ while a 20–50MB HEIC decodes.
    private func loadFeaturedImageFallback() {
        guard let featured = viewModel.getFeaturedItem(for: yearsAgo) else { return }

        // Use the same display-size target as the startup prefetch so both paths hit
        // the same cache entry. If we used a smaller card-sized target here, PhotoKit
        // would decode a second (lower-quality) image for the same asset, and years
        // that fell through to the fallback (e.g. years 4+ not in the startup set)
        // would end up looking softer than years that were prefetched.
        let targetSize = viewModel.carouselDisplayImageSize

        viewModel.requestCarouselImage(for: featured.asset, targetSize: targetSize) { image, isDegraded in
            guard let image = image else { return }
            if isDegraded {
                // Low-res proxy: show instantly, no animation (this is the "first photo").
                cardImage = image
            } else {
                // High-res final: brief crossfade so the snap from blurry → sharp is smooth.
                // Also hoist into preloadedFeaturedImages so swiping back to this card
                // (or the detail view hero transition) picks up the sharp cached image
                // instead of re-triggering the fallback.
                viewModel.storePreloadedFeaturedImage(image, for: yearsAgo)
                withAnimation(.easeIn(duration: 0.2)) {
                    cardImage = image
                }
            }
        }
    }

    // MARK: - Glow Border

    private var lightningGlowBorder: some View {
        ZStack {
            // Breathing base glow
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    Color(red: 0.70, green: 0.82, blue: 1.0).opacity(glowBreath),
                    lineWidth: 2.5
                )
                .blur(radius: 6)

            // Traveling spotlight — one bright blue spot tracing the border
            TimelineView(.animation) { timeline in
                let seconds = timeline.date.timeIntervalSinceReferenceDate
                let angle = seconds.truncatingRemainder(dividingBy: 4.0) / 4.0 * 360

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.0),
                                Color.white.opacity(0.0),
                                Color.white.opacity(0.0),
                                Color(red: 0.50, green: 0.65, blue: 1.0).opacity(0.5),
                                Color(red: 0.55, green: 0.75, blue: 1.0).opacity(0.95),
                                Color(red: 0.50, green: 0.65, blue: 1.0).opacity(0.5),
                                Color.white.opacity(0.0),
                                Color.white.opacity(0.0),
                                Color.white.opacity(0.0),
                                Color.white.opacity(0.0),
                                Color.white.opacity(0.0),
                                Color.white.opacity(0.0)
                            ]),
                            center: .center,
                            startAngle: .degrees(angle),
                            endAngle: .degrees(angle + 360)
                        ),
                        lineWidth: 3
                    )
                    .blur(radius: 5)
            }
        }
    }

    private func startGlowAnimations() {
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
            glowBreath = 0.9
        }
    }
}
