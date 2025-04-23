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
    
    // Add computed property to get the formatted date
    private var formattedDate: String {
        let calendar = Calendar.current
        let today = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: today)
        components.year = (components.year ?? 0) - yearsAgo
        
        guard let pastDate = calendar.date(from: components) else {
            return ""
        }
        
        return getFormattedDateWithOrdinal(from: pastDate)
    }
    
    // Helper to format date with ordinal suffix
    private func getFormattedDateWithOrdinal(from date: Date) -> String {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: date)
        
        // Get ordinal suffix for the day
        let suffix: String
        switch day {
        case 1, 21, 31: suffix = "st"
        case 2, 22: suffix = "nd"
        case 3, 23: suffix = "rd"
        default: suffix = "th"
        }
        
        // Create the formatted date with ordinal
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM d"
        let baseDate = dateFormatter.string(from: date)
        
        // Add year separately
        let year = calendar.component(.year, from: date)
        
        return "\(baseDate)\(suffix), \(year)"
    }

    // Computed property to determine the items shown in the grid
    var allGridItems: [MediaItem] {
        // Print statements removed for brevity, assuming logic is correct now
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
    // Define a fixed 2-column grid like Apple Photos on iPhone
    let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 6), // Reduced spacing between columns
        GridItem(.flexible())
    ]
    // Define VERTICAL spacing between rows
    let verticalSpacing: CGFloat = 6 // Reduced spacing between rows
    // Define outer padding around the grid
    let gridOuterPaddingValue: CGFloat = 6
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
        return Double(rowIndex) * 0.08 // Reverted from 0.12 back to 0.08
    }

    var body: some View {
        ZStack {
            // --- Fullscreen Featured Item (Splash View) ---
            if let item = featuredItem, !hasTappedSplash {
                FeaturedYearFullScreenView(
                    item: item,
                    yearsAgo: yearsAgo
                ) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        viewModel.markSplashDismissed(for: yearsAgo)
                        // Reset animation states when transitioning from splash screen
                        dateAppeared = false
                        dateBounce = false
                        animatedItems.removeAll() // Reset animated items for cascading effect
                        
                        // Schedule animation sequence after splash screen disappears
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation {
                                dateAppeared = true
                            }
                            // Add a little bounce effect
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                withAnimation {
                                    dateBounce = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation {
                                        dateBounce = false
                                    }
                                }
                            }
                        }
                    }
                }
                
                .allowsHitTesting(true)
                .transition(.opacity)

            // --- Grid View Content ---
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        // --- Title with Date ---
                        VStack(spacing: 3) {
                            Text("\(yearsAgo) Year\(yearsAgo == 1 ? "" : "s") Ago")
                                .font(.largeTitle.bold())
                                .padding(.top, 16)
                            
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
                                .shadow(color: .black.opacity(0.2), radius: 1, x: 0.5, y: 0.5)
                                .scaleEffect(dateAppeared ? (dateBounce ? 1.05 : 1.0) : 0.8)
                                .rotationEffect(dateAppeared ? .zero : .degrees(-3))
                                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: dateAppeared)
                                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: dateBounce)
                                .onAppear {
                                    if hasTappedSplash {
                                        // Delayed sequence of animations when date appears
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            withAnimation {
                                                dateAppeared = true
                                            }
                                            // Add a little bounce effect
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                                withAnimation {
                                                    dateBounce = true
                                                }
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                    withAnimation {
                                                        dateBounce = false
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 20) // Increased padding between date and grid
                        .opacity(hasTappedSplash ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.4).delay(0.1), value: hasTappedSplash)

                        // --- Photo Grid ---
                        LazyVGrid(
                            columns: columns,
                            spacing: verticalSpacing
                        ) {
                            ForEach(Array(allGridItems.enumerated()), id: \.element.id) { index, item in
                                GridItemView(viewModel: viewModel, item: item) {
                                    selectedItemForDetail = item
                                }
                                // Force square aspect ratio
                                .aspectRatio(1, contentMode: .fill)
                                .frame(maxWidth: .infinity)
                                .clipShape(Rectangle())
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1) // Subtle shadow for depth
                                .offset(y: animatedItems.contains(item.id) ? 0 : -50)
                                .opacity(animatedItems.contains(item.id) ? 1 : 0)
                                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(calculateDelay(for: index)), value: animatedItems.contains(item.id))
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
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { // The 0.3s delay before marking done
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
                        .padding(.horizontal, gridOuterPaddingValue) // Consistent horizontal padding
                        
                        // --- Footer Text ---
                        Text("Make More Memories!")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .padding()
                            .opacity(hasTappedSplash ? 1.0 : 0.0)
                            .animation(.easeInOut(duration: 0.4).delay(0.3), value: hasTappedSplash)

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

// Ensure your GridItemView.swift still uses .scaledToFit() for the Image
// Ensure you have definitions for MediaItem, PhotoViewModel, FeaturedYearFullScreenView, MediaDetailView


