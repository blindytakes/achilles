// Throwbaks/Achilles/Views/LoadedYearContentView.swift

import SwiftUI
import Photos

struct LoadedYearContentView: View {
    @ObservedObject var viewModel: PhotoViewModel
    let yearsAgo: Int

    // --- Computed properties to access state ---
    private var pageState: PageState {
        viewModel.pageStateByYear[yearsAgo] ?? .idle
    }
    private var featuredItemFromState: MediaItem? {
        if case .loaded(let featured, _) = pageState { return featured }
        return nil
    }
    private var gridItemsFromState: [MediaItem] {
        if case .loaded(_, let grid) = pageState { return grid }
        return []
    }
    // --- End Computed properties ---

    private var shouldAnimateGrid: Bool { !viewModel.gridAnimationDone.contains(yearsAgo) }
    private var hasTappedSplash: Bool { viewModel.dismissedSplashForYearsAgo.contains(yearsAgo) }
    @State private var selectedItemForDetail: MediaItem? = nil
    @State private var dateAppeared = false
    @State private var dateBounce = false

    // MARK: - Constants
    private let mainVStackSpacing: CGFloat = 0
    private let titleVStackSpacing: CGFloat = 3
    private let titleTopPadding: CGFloat = 16
    private let titleBottomPadding: CGFloat = 15
    private let gridColumnSpacing: CGFloat = 5
    private let gridRowSpacing: CGFloat = 4
    private let gridHorizontalPadding: CGFloat = 6
    private let footerVerticalPadding: CGFloat = 16
    private let gridItemAspectRatio: CGFloat = 1.0
    private let gridItemShadowOpacity: Double = 0.1
    private let gridItemShadowRadius: CGFloat = 2
    private let gridItemShadowYOffset: CGFloat = 1
    private let gridItemAppearOffset: CGFloat = -50
    private let dateAppearRotation: Double = -3
    private let dateBounceScale: CGFloat = 1.05
    private let dateNonBounceScale: CGFloat = 1.0
    private let dateAppearScale: CGFloat = 0.8
    private let visibleOpacity: Double = 1.0
    private let hiddenOpacity: Double = 0.0
    private let dateTextShadowOpacity: Double = 0.2
    private let dateTextShadowRadius: CGFloat = 1
    private let dateTextShadowXOffset: CGFloat = 0.5
    private let dateTextShadowYOffset: CGFloat = 0.5
    private let splashTransitionDelay: Double = 0.4
    private let dateAppearSpringResponse: Double = 0.5
    private let dateAppearSpringDamping: Double = 0.7
    private let dateAppearDelay: Double = 0.3
    private let dateBounceDelay: Double = 0.4
    private let dateBounceSpringResponse: Double = 0.25
    private let dateBounceSpringDamping: Double = 0.6
    private let dateBounceEndDelay: Double = 0.1
    private let gridItemSpringResponse: Double = 0.6
    private let gridItemSpringDamping: Double = 0.7
    private let gridItemAnimationBaseDelay: Double = 0.08
    private let gridAnimationMarkDoneDelay: Double = 0.3
    private let contentFadeInDuration: Double = 0.4
    private let contentFadeInDelay: Double = 0.1
    private let footerFadeInDelay: Double = 0.3
    private let splashDismissSpringDamping: Double = 0.8


    private var formattedDate: String {
        let calendar = Calendar.current
        let today = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: today)
        components.year = (components.year ?? 0) - yearsAgo
        guard let pastDate = calendar.date(from: components) else { return "" }
        return pastDate.formatMonthDayOrdinalAndYear()
    }

    var allGridItems: [MediaItem] {
        if hasTappedSplash {
            if let featured = featuredItemFromState { return [featured] + gridItemsFromState }
            else { return gridItemsFromState }
        } else { return [] }
    }

    // --- Grid Layout Configuration ---
    // <<< --- CONFIRMED IMPLEMENTATION --- >>>
    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: gridColumnSpacing), // Defines first column
            GridItem(.flexible(), spacing: gridColumnSpacing)  // Defines second column
        ]
    }
    // <<< --- END CONFIRMED IMPLEMENTATION --- >>>
    let gridOuterPadding: Edge.Set = .horizontal // Keep if used, otherwise remove
    let itemCornerRadius: CGFloat = 0


    // Animation properties for cascading effect
    @State private var animatedItems: Set<String> = []

    // Function to calculate delay for each item
    private func calculateDelay(for index: Int) -> Double {
        let rowIndex = index / 2
        return Double(rowIndex) * gridItemAnimationBaseDelay
    }

    var body: some View {
        ZStack {
            switch pageState {
            case .idle, .loading:
                SkeletonView()
                    .transition(.opacity.animation(.easeInOut))

            case .loaded(let featured, _):
                ZStack {
                    // Splash View
                    if let item = featured, !hasTappedSplash {
                        let imageToPreload = viewModel.getPreloadedFeaturedImage(for: yearsAgo)
                        FeaturedYearFullScreenView(
                            item: item,
                            yearsAgo: yearsAgo,
                            onTap: { // Action when splash is tapped
                                withAnimation(.spring(response: dateAppearSpringResponse, dampingFraction: splashDismissSpringDamping)) {
                                    viewModel.markSplashDismissed(for: yearsAgo)
                                    // Reset animation states
                                    dateAppeared = false; dateBounce = false; animatedItems.removeAll()
                                    // Schedule animation sequence
                                    DispatchQueue.main.asyncAfter(deadline: .now() + splashTransitionDelay) {
                                        withAnimation { dateAppeared = true }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + dateBounceDelay) {
                                            withAnimation { dateBounce = true }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + dateBounceEndDelay) {
                                                withAnimation { dateBounce = false }
                                            }
                                        }
                                    }
                                }
                            },
                            viewModel: viewModel,
                            preloadedImage: imageToPreload
                        )
                        .allowsHitTesting(true)
                        .transition(.opacity)

                    // Grid View Content
                    } else {
                        ScrollView(.vertical) {
                            VStack(spacing: mainVStackSpacing) {
                                // Title and Date
                                VStack(spacing: titleVStackSpacing) {
                                    Text("\(yearsAgo) Year\(yearsAgo == 1 ? "" : "s") Ago")
                                        .font(.largeTitle.bold())
                                        .padding(.top, titleTopPadding)
                                    Text(formattedDate)
                                        .font(.title2)
                                        .fontWeight(.medium)
                                        .italic()
                                        .foregroundStyle(LinearGradient(colors: [.primary, .primary.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .fontDesign(.serif)
                                        .shadow(color: .black.opacity(dateTextShadowOpacity), radius: dateTextShadowRadius, x: dateTextShadowXOffset, y: dateTextShadowYOffset)
                                        .scaleEffect(dateAppeared ? (dateBounce ? dateBounceScale : dateNonBounceScale) : dateAppearScale)
                                        .rotationEffect(dateAppeared ? .zero : .degrees(dateAppearRotation))
                                        .animation(.spring(response: dateAppearSpringResponse, dampingFraction: dateAppearSpringDamping), value: dateAppeared)
                                        .animation(.spring(response: dateBounceSpringResponse, dampingFraction: dateBounceSpringDamping), value: dateBounce)
                                        .onAppear { // Date animation trigger
                                             guard hasTappedSplash else { return }
                                             if !viewModel.gridDateAnimationsCompleted.contains(yearsAgo) {
                                                 print("▶️ Grid Date Animation needed for \(yearsAgo)")
                                                 viewModel.gridDateAnimationsCompleted.insert(yearsAgo)
                                                 DispatchQueue.main.asyncAfter(deadline: .now() + dateAppearDelay) {
                                                     withAnimation(.spring(response: dateAppearSpringResponse, dampingFraction: dateAppearSpringDamping)) { dateAppeared = true }
                                                     DispatchQueue.main.asyncAfter(deadline: .now() + dateBounceDelay) {
                                                         withAnimation(.spring(response: dateBounceSpringResponse, dampingFraction: dateBounceSpringDamping)) { dateBounce = true }
                                                         DispatchQueue.main.asyncAfter(deadline: .now() + dateBounceEndDelay) {
                                                             withAnimation(.spring(response: dateBounceSpringResponse, dampingFraction: dateBounceSpringDamping)) { dateBounce = false }
                                                         }
                                                     }
                                                 }
                                             } else {
                                                 print("⏸️ Grid Date Animation already done for \(yearsAgo)")
                                                 dateAppeared = true; dateBounce = false
                                             }
                                         }
                                }
                                .padding(.bottom, titleBottomPadding)
                                .opacity(hasTappedSplash || featured == nil ? visibleOpacity : hiddenOpacity)
                                .animation(.easeInOut(duration: contentFadeInDuration).delay(contentFadeInDelay), value: hasTappedSplash || featured == nil)

                                // Photo Grid
                                LazyVGrid(columns: columns, spacing: gridRowSpacing) { // Uses the 'columns' property
                                    ForEach(Array(allGridItems.enumerated()), id: \.element.id) { index, item in
                                        GridItemView(viewModel: viewModel, item: item) { selectedItemForDetail = item }
                                        .aspectRatio(gridItemAspectRatio, contentMode: .fill)
                                        .clipShape(Rectangle())
                                        .shadow(color: .black.opacity(gridItemShadowOpacity), radius: gridItemShadowRadius, x: 0, y: gridItemShadowYOffset)
                                        .offset(y: animatedItems.contains(item.id) ? 0 : gridItemAppearOffset)
                                        .opacity(animatedItems.contains(item.id) ? visibleOpacity : hiddenOpacity)
                                        .animation(.spring(response: gridItemSpringResponse, dampingFraction: gridItemSpringDamping).delay(calculateDelay(for: index)), value: animatedItems.contains(item.id))
                                        .onAppear { // Grid item animation trigger
                                             print("onAppear: yearsAgo=\(yearsAgo), item=\(item.id), index=\(index), shouldAnimateGrid=\(shouldAnimateGrid)")
                                             guard shouldAnimateGrid else {
                                                 print("--> Skipping animation for yearsAgo=\(yearsAgo), inserting item \(item.id) immediately.")
                                                 animatedItems.insert(item.id); return
                                             }
                                             print("--> Starting animation for yearsAgo=\(yearsAgo), item=\(item.id), index=\(index)")
                                             let delay = calculateDelay(for: index)
                                             DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                                 print("--> Delayed insert for yearsAgo=\(yearsAgo), item=\(item.id), index=\(index)")
                                                 animatedItems.insert(item.id)
                                                 let isLastItem = (index == allGridItems.count - 1)
                                                 print("--> Checking if last item for yearsAgo=\(yearsAgo): index=\(index), count=\(allGridItems.count), isLast=\(isLastItem)")
                                                 if isLastItem {
                                                     print("--> Condition MET for last item yearsAgo=\(yearsAgo)! Scheduling insertion into gridAnimationDone.")
                                                     DispatchQueue.main.asyncAfter(deadline: .now() + gridAnimationMarkDoneDelay) {
                                                         print("--> EXECUTING insert for yearsAgo=\(yearsAgo) into gridAnimationDone.")
                                                         viewModel.gridAnimationDone.insert(yearsAgo)
                                                         print("--> gridAnimationDone now contains: \(viewModel.gridAnimationDone)")
                                                     }
                                                 }
                                             }
                                         } // End onAppear
                                    } // End ForEach
                                } // End LazyVGrid
                                .padding(.horizontal, gridHorizontalPadding)

                                // Footer Text
                                Text("Make More Memories!")
                                    .font(.callout)
                                    .foregroundColor(.primary)
                                    .padding(.vertical, footerVerticalPadding)
                                    .opacity(hasTappedSplash || featured == nil ? visibleOpacity : hiddenOpacity)
                                    .animation(.easeInOut(duration: contentFadeInDuration).delay(footerFadeInDelay), value: hasTappedSplash || featured == nil)

                                Spacer()
                            } // End main VStack
                        } // End ScrollView
                        .transition(.opacity)
                    } // End else (Grid View Content)
                } // End ZStack (Splash or Grid)

            case .empty:
                EmptyYearView()
                    .transition(.opacity.animation(.easeInOut))

            case .error(let message):
                ErrorYearView(viewModel: viewModel, yearsAgo: yearsAgo, errorMessage: message)
                    .transition(.opacity.animation(.easeInOut))
            } // End switch pageState
        } // End outer ZStack
        .sheet(item: $selectedItemForDetail) { itemToDisplay in
             let itemsForDetail = (featuredItemFromState.map { [$0] } ?? []) + gridItemsFromState
             MediaDetailView(viewModel: viewModel, itemsForYear: itemsForDetail, selectedItemID: itemToDisplay.id)
        }
        .onDisappear { selectedItemForDetail = nil }
    } // End body
} 
