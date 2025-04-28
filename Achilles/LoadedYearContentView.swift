import SwiftUI
import Photos

struct LoadedYearContentView: View {
    @ObservedObject var viewModel: PhotoViewModel
    let yearsAgo: Int
    let featuredItem: MediaItem?
    let gridItems: [MediaItem]

    private var shouldAnimateGrid: Bool {
        !viewModel.gridAnimationDone.contains(yearsAgo)
    }
    
    private var hasTappedSplash: Bool {
        viewModel.dismissedSplashForYearsAgo.contains(yearsAgo)
    }
    @State private var selectedItemForDetail: MediaItem? = nil
    
    // Add animation states
    @State private var dateAppeared = false
    @State private var dateBounce = false
    // MARK: - Constants

       // Layout
       private let mainVStackSpacing: CGFloat = 0
       private let titleVStackSpacing: CGFloat = 3
       private let titleTopPadding: CGFloat = 16
       private let titleBottomPadding: CGFloat = 20
       private let gridColumnSpacing: CGFloat = 6 // Matches spacing in columns definition
       private let gridRowSpacing: CGFloat = 6 // Vertical spacing for LazyVGrid
       private let gridHorizontalPadding: CGFloat = 6 // Outer horizontal padding for LazyVGrid
       private let footerVerticalPadding: CGFloat = 16 // Replaces default .padding()

       // Animation Timings
       private let splashTransitionDelay: Double = 0.4
       private let dateAppearSpringResponse: Double = 0.5
       private let dateAppearSpringDamping: Double = 0.7
       private let dateAppearDelay: Double = 0.3 // Delay after splash dismiss
       private let dateBounceDelay: Double = 0.4 // Delay after date appear
       private let dateBounceSpringResponse: Double = 0.25
       private let dateBounceSpringDamping: Double = 0.6
       private let dateBounceEndDelay: Double = 0.1 // Delay before bounce settles
       private let gridItemSpringResponse: Double = 0.6
       private let gridItemSpringDamping: Double = 0.7
       private let gridItemAnimationBaseDelay: Double = 0.08
       private let gridAnimationMarkDoneDelay: Double = 0.3 // Delay before marking animation set done
       private let contentFadeInDuration: Double = 0.4
       private let contentFadeInDelay: Double = 0.1
       private let footerFadeInDelay: Double = 0.3
       private let splashDismissSpringDamping: Double = 0.8 // Specific damping for splash dismiss animation

       // Style & Visuals
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

    

    private var formattedDate: String {
        let calendar = Calendar.current
        let today = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: today)
        components.year = (components.year ?? 0) - yearsAgo

        guard let pastDate = calendar.date(from: components) else {
            return ""
        }
        // Use the new extension method directly:
        return pastDate.formatMonthDayOrdinalAndYear()
    }

    // Computed property to determine the items shown in the grid
    var allGridItems: [MediaItem] {
        if hasTappedSplash {
            if let featured = featuredItem {
                return [featured] + gridItems
            } else {
                return gridItems
            }
        } else {
            return [] // Return empty when splash screen is visible
        }
    }

    // --- Grid Layout Configuration ---
    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: gridColumnSpacing),
            GridItem(.flexible(), spacing: gridColumnSpacing)
        ]
    }
    let gridOuterPadding: Edge.Set = .horizontal
    // Define corner radius for grid items
    let itemCornerRadius: CGFloat = 0 // No rounded corners to maximize photo area
    // ---------------------------------
    
    // Animation properties for cascading effect
    @State private var animatedItems: Set<String> = []
    
    // Function to calculate delay for each item
    private func calculateDelay(for index: Int) -> Double {
        // The delay increases based on the row position (every 2 items)
        let rowIndex = index / 2
        return Double(rowIndex) * gridItemAnimationBaseDelay
    }

    var body: some View {
        ZStack {
            // --- Fullscreen Featured Item (Splash View) ---
            if let item = featuredItem, !hasTappedSplash {
                FeaturedYearFullScreenView(
                    item: item,
                    yearsAgo: yearsAgo,
                    onTap: {
                        
                        withAnimation(.spring(response: dateAppearSpringResponse, dampingFraction: splashDismissSpringDamping)) {
                            viewModel.markSplashDismissed(for: yearsAgo)
                            // Reset animation states when transitioning from splash screen
                            dateAppeared = false
                            dateBounce = false
                            animatedItems.removeAll() // Reset animated items for cascading effect
                            
                            // Schedule animation sequence after splash screen disappears
                            DispatchQueue.main.asyncAfter(deadline: .now() + splashTransitionDelay) {
                                withAnimation {
                                    dateAppeared = true
                                }
                                // Add a little bounce effect
                                DispatchQueue.main.asyncAfter(deadline: .now() + dateBounceDelay) {
                                    withAnimation {
                                        dateBounce = true
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + dateBounceEndDelay) {
                                        withAnimation {
                                            dateBounce = false
                                        }
                                    }
                                }
                            }
                        }
                    },
                    viewModel: viewModel
                )
                
                .allowsHitTesting(true)
                .transition(.opacity)

            // --- Grid View Content ---
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: mainVStackSpacing) {
                        VStack(spacing: titleVStackSpacing) {
                            Text("\(yearsAgo) Year\(yearsAgo == 1 ? "" : "s") Ago")
                                .font(.largeTitle.bold())
                                .padding(.top, titleTopPadding)
                            
                            Text(formattedDate)
                                .font(.title2)
                                .fontWeight(.medium)
                                .italic()
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.primary, .primary.opacity(0.85)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .fontDesign(.serif)
                                .shadow(color: .black.opacity(dateTextShadowOpacity), radius: dateTextShadowRadius, x: dateTextShadowXOffset, y: dateTextShadowYOffset)
                                .scaleEffect(
                                  dateAppeared
                                    ? (dateBounce ? dateBounceScale : dateNonBounceScale)
                                    : dateAppearScale
                                )
                                .rotationEffect(dateAppeared ? .zero : .degrees(dateAppearRotation))
                                .animation(.spring(response: dateAppearSpringResponse, dampingFraction: dateAppearSpringDamping), value: dateAppeared)
                                .animation(.spring(response: dateBounceSpringResponse, dampingFraction: dateBounceSpringDamping), value: dateBounce)
                            
                                .onAppear {
                                 // Ensure we only attempt animation after splash is dismissed
                                 guard hasTappedSplash else { return }

                                 // Check if animation for THIS yearsAgo has already run
                                 if !viewModel.gridDateAnimationsCompleted.contains(yearsAgo) {
                                     // --- Animation Needed ---
                                     print("▶️ Grid Date Animation needed for \(yearsAgo)")

                                     // Mark as completed in the ViewModel IMMEDIATELY
                                     // So if .onAppear somehow fires again quickly, it won't re-trigger
                                     viewModel.gridDateAnimationsCompleted.insert(yearsAgo)

                                     // Schedule the animation sequence using DispatchQueue
                                     DispatchQueue.main.asyncAfter(deadline: .now() + dateAppearDelay) {
                                         withAnimation(.spring(response: dateAppearSpringResponse, dampingFraction: dateAppearSpringDamping)) {
                                             dateAppeared = true
                                         }

                                         // Schedule the bounce sequence
                                         DispatchQueue.main.asyncAfter(deadline: .now() + dateBounceDelay) {
                                             withAnimation(.spring(response: dateBounceSpringResponse, dampingFraction: dateBounceSpringDamping)) {
                                                 dateBounce = true
                                             }
                                             DispatchQueue.main.asyncAfter(deadline: .now() + dateBounceEndDelay) {
                                                 withAnimation(.spring(response: dateBounceSpringResponse, dampingFraction: dateBounceSpringDamping)) {
                                                     dateBounce = false
                                                 }
                                             }
                                         }
                                     }
                                 } else {
                                     // --- Animation Already Done ---
                                     print("⏸️ Grid Date Animation already done for \(yearsAgo)")
                                     // Set the final appearance state directly, without animations
                                     // Ensures text is visible if user swipes back quickly
                                     dateAppeared = true
                                     dateBounce = false // Ensure bounce state is non-bounced
                                 }
                             }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, titleBottomPadding)
                        .opacity(hasTappedSplash ? visibleOpacity : hiddenOpacity)
                        .animation(.easeInOut(duration: contentFadeInDuration).delay(contentFadeInDelay), value: hasTappedSplash)

                        // --- Photo Grid ---
                        LazyVGrid(
                            columns: columns,
                            spacing: gridRowSpacing)
                        {
                            ForEach(Array(allGridItems.enumerated()), id: \.element.id) { index, item in
                                GridItemView(viewModel: viewModel, item: item) {
                                    selectedItemForDetail = item
                                }
                                // Force square aspect ratio
                                .aspectRatio(gridItemAspectRatio, contentMode: .fill)
                                .frame(maxWidth: .infinity)
                                .clipShape(Rectangle())
                                .shadow(color: .black.opacity(gridItemShadowOpacity), radius: gridItemShadowRadius, x: 0, y: gridItemShadowYOffset) // Subtle shadow for depth
                                .offset(y: animatedItems.contains(item.id) ? 0 : gridItemAppearOffset)
                                .opacity(animatedItems.contains(item.id) ? visibleOpacity : hiddenOpacity)
                                .animation(.spring(response: gridItemSpringResponse, dampingFraction: gridItemSpringDamping).delay(calculateDelay(for: index)), value: animatedItems.contains(item.id))
                                .onAppear {
                                    // Print at the very start
                                    print("onAppear: yearsAgo=\(yearsAgo), item=\(item.id), index=\(index), shouldAnimateGrid=\(shouldAnimateGrid)")

                                    guard shouldAnimateGrid else {
                                        // Print if skipping animation
                                        print("--> Skipping animation for yearsAgo=\(yearsAgo), inserting item \(item.id) immediately.")
                                        animatedItems.insert(item.id)
                                        return
                                    }

                                    // Print if starting animation
                                    print("--> Starting animation for yearsAgo=\(yearsAgo), item=\(item.id), index=\(index)")
                                    let delay = calculateDelay(for: index)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                        // Print when item appears after delay
                                        print("--> Delayed insert for yearsAgo=\(yearsAgo), item=\(item.id), index=\(index)")
                                        animatedItems.insert(item.id)

                                        // *** CRITICAL DEBUG AREA ***
                                        let isLastItem = (index == allGridItems.count - 1)
                                        print("--> Checking if last item for yearsAgo=\(yearsAgo): index=\(index), count=\(allGridItems.count), isLast=\(isLastItem)")

                                        if isLastItem {
                                            print("--> Condition MET for last item yearsAgo=\(yearsAgo)! Scheduling insertion into gridAnimationDone.")
                                            DispatchQueue.main.asyncAfter(deadline: .now() + gridAnimationMarkDoneDelay) {
                                                print("--> EXECUTING insert for yearsAgo=\(yearsAgo) into gridAnimationDone.")
                                                viewModel.gridAnimationDone.insert(yearsAgo)
                                                // Optionally print the set content AFTER insertion
                                                print("--> gridAnimationDone now contains: \(viewModel.gridAnimationDone)")
                                            }
                                        }
                                        // *** END CRITICAL DEBUG AREA ***
                                    }
                                }

                            }
                        }
                        .padding(.horizontal, gridHorizontalPadding)
                        
                        // --- Footer Text ---
                        Text("Make More Memories!")
                            .font(.callout)
                            .foregroundColor(.primary)
                            .padding(footerVerticalPadding)
                            .opacity(hasTappedSplash ? visibleOpacity : hiddenOpacity)
                            .animation(.easeInOut(duration: contentFadeInDuration).delay(footerFadeInDelay), value: hasTappedSplash)

                        Spacer()
                    }
                }
                .transition(.opacity)
            }
        }
        // --- Detail View Sheet ---
        .sheet(item: $selectedItemForDetail) { itemToDisplay in
            MediaDetailView(
                viewModel: viewModel,
                itemsForYear: (featuredItem.map { [$0] } ?? []) + gridItems,
                selectedItemID: itemToDisplay.id
            )
        }
        .onDisappear {
            selectedItemForDetail = nil
        }
    }
}


