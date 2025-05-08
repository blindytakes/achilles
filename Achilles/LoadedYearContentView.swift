// LoadedYearContentView.swift
//
// This view handles the presentation of photos from a specific year in the past.
// It has two main visual states:
//
// 1. Splash Screen: Initially shows a featured photo in full-screen mode
//    until the user taps to dismiss it
//
// 2. Grid View: After splash dismissal, displays:
//    - Header with years ago and formatted date (with entrance animation)
//    - Photo grid showing the featured photo and additional photos
//    - Footer message
//
// The view handles state transitions and animations:
// - Manages the transition from splash to grid view
// - Animates the date header with a spring and bounce effect
// - Shows detail view when a photo is tapped
//
// All UI elements and animations are managed through SwiftUI's declarative syntax,
// with efficient state tracking and smooth transitions between view states.


import SwiftUI
import Photos

struct LoadedYearContentView: View {
    @ObservedObject var viewModel: PhotoViewModel
    let yearsAgo: Int

    // MARK: - Computed properties
    private var pageState: PageState {
        viewModel.pageStateByYear[yearsAgo] ?? .idle
    }
    private var featuredItem: MediaItem? {
        if case .loaded(let featured, _) = pageState { return featured }
        return nil
    }
    private var gridItems: [MediaItem] {
        if case .loaded(_, let items) = pageState { return items }
        return []
    }
    private var hasDismissedSplash: Bool {
        viewModel.dismissedSplashForYearsAgo.contains(yearsAgo)
    }
    private var allGridItems: [MediaItem] {
        var items = [MediaItem]()
        if let featured = featuredItem { items.append(featured) }
        items.append(contentsOf: gridItems)
        return items
    }

    // MARK: - Animation state
    @State private var didAnimateDate = false
    @State private var dateAppeared = false
    @State private var dateBounce = false
    @State private var selectedDetail: MediaItem?

    // MARK: - Animation constants
    private let fadeDuration: Double = 1.0
    private let dateSpringResponse: Double = 0.7
    private let dateSpringDamping: Double = 0.9
    private let dateBounceDelay: Double = 0.2
    private let dateBounceEnd: Double = 0.05
    private let dateAppearRotation: Double = -1
    private let dateAppearScale: CGFloat = 0.95
    private let dateBounceScale: CGFloat = 1.02

    // MARK: - Date formatting
    private var formattedDate: String {
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month, .day], from: Date())
        comps.year = (comps.year ?? 0) - yearsAgo
        guard let past = calendar.date(from: comps) else { return "" }
        return past.monthDayWithOrdinalAndYear()
    }

    // MARK: - Grid layout
    private let columns = [
        GridItem(.flexible(), spacing: 5),
        GridItem(.flexible(), spacing: 5)
    ]

    // MARK: - Grid view (always present underneath splash)
    private var gridView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Date header only after splash is dismissed
                if hasDismissedSplash {
                    VStack(spacing: 3) {
                        Text("\(yearsAgo) Year\(yearsAgo == 1 ? "" : "s") Ago")
                            .font(.largeTitle.bold())
                            .padding(.top, 16)

                        Text(formattedDate)
                            .scaleEffect(dateAppeared ? (dateBounce ? dateBounceScale : 1) : dateAppearScale)
                            .rotationEffect(dateAppeared ? .zero : .degrees(dateAppearRotation))
                            .animation(.spring(response: dateSpringResponse, dampingFraction: dateSpringDamping),
                                       value: dateAppeared)
                            .animation(.spring(response: dateSpringResponse, dampingFraction: dateSpringDamping),
                                       value: dateBounce)
                    }
                    .padding(.bottom, 12)
                    // Trigger the date animation when the splash goes away
                    .onChange(of: hasDismissedSplash) { didDismiss in
                        guard didDismiss, !didAnimateDate else { return }
                        didAnimateDate = true
                        withAnimation {
                            dateAppeared = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + dateBounceDelay) {
                            withAnimation { dateBounce = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + dateBounceEnd) {
                                withAnimation { dateBounce = false }
                            }
                        }
                    }
                }

                // Your grid
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(allGridItems, id: \.id) { item in
                        GridItemView(viewModel: viewModel, item: item) {
                            selectedDetail = item
                        }
                        .animation(nil, value: allGridItems)   // disable insertion animations
                        .aspectRatio(1, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                    }
                }
                .padding(.horizontal, 6)

                // Footer after splash
                if hasDismissedSplash {
                    Text("Make More Memories!")
                        .font(.subheadline)
                        .padding(.vertical, 12)
                }

                Spacer()
            }
            // Fade the grid in once splash is dismissed
            .opacity(hasDismissedSplash ? 1 : 0)
        }
    }

    var body: some View {
        ZStack {
            gridView

            // Splash overlay
            if let featured = featuredItem, !hasDismissedSplash {
                FeaturedYearFullScreenView(
                    item: featured,
                    yearsAgo: yearsAgo,
                    onTap: {
                        withAnimation(.easeInOut(duration: fadeDuration)) {
                            viewModel.markSplashDismissed(for: yearsAgo)
                        }
                    },
                    viewModel: viewModel,
                    preloadedImage: viewModel.getPreloadedFeaturedImage(for: yearsAgo)
                )
                .transition(.opacity)
            }
        }
        .sheet(item: $selectedDetail) { item in
            MediaDetailView(
                viewModel: viewModel,
                itemsForYear: allGridItems,
                selectedItemID: item.id
            )
        }
        .onDisappear { selectedDetail = nil }
    }
}

