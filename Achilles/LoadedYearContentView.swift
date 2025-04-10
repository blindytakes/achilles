import SwiftUI
import Photos

struct LoadedYearContentView: View {
    @ObservedObject var viewModel: PhotoViewModel
    let yearsAgo: Int
    let featuredItem: MediaItem?
    let gridItems: [MediaItem]

    @State private var hasTappedSplash = false
    @State private var selectedItemForDetail: MediaItem? = nil

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
    // Define 2 columns with REDUCED spacing between them
    let columns: [GridItem] = [
        // Set HORIZONTAL spacing between columns (e.g., 4 points)
        GridItem(.flexible(), spacing: 5), // <-- REDUCED horizontal spacing
        GridItem(.flexible())
    ]
    // Define REDUCED VERTICAL spacing between rows (e.g., 4 points)
    let verticalSpacing: CGFloat = 6 // <-- REDUCED vertical spacing
    // Define outer padding around the grid (e.g., 4 points horizontal)
    let gridOuterPaddingValue: CGFloat = 2
    let gridOuterPadding: Edge.Set = .horizontal
    // Define corner radius for grid items
    let itemCornerRadius: CGFloat = 4 // Keep or adjust corner radius
    // ---------------------------------

    var body: some View {
        ZStack {
            // --- Fullscreen Featured Item (Splash View) ---
            if let item = featuredItem, !hasTappedSplash {
                FeaturedYearFullScreenView(
                    item: item,
                    yearsAgo: yearsAgo
                ) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        hasTappedSplash = true
                    }
                }
                .gesture(
                    DragGesture().onEnded { _ in } , including: .subviews
                )
                .allowsHitTesting(true)
                .transition(.opacity)

            // --- Grid View Content ---
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        // --- Title ---
                        Text("\(yearsAgo) Year\(yearsAgo == 1 ? "" : "s") Ago")
                            .font(.largeTitle.bold())
                            .padding(.top)
                            .padding(.bottom) // Keep padding below title
                            .opacity(hasTappedSplash ? 1.0 : 0.0)
                            .animation(.easeInOut(duration: 0.4).delay(0.1), value: hasTappedSplash)

                        // --- Photo Grid ---
                        LazyVGrid(
                            columns: columns,           // Use the defined columns
                            spacing: verticalSpacing    // Use the defined VERTICAL spacing
                        ) {
                            ForEach(allGridItems) { item in
                                // Make sure GridItemView uses .scaledToFit() internally
                                GridItemView(viewModel: viewModel, item: item) {
                                    selectedItemForDetail = item
                                }
                                .clipShape(RoundedRectangle(cornerRadius: itemCornerRadius)) // Keep corner radius
                                .animation(.easeIn(duration: 0.2).delay(Double.random(in: 0...0.2)), value: hasTappedSplash)
                                .transition(.opacity)
                            }
                        }
                        // Apply outer padding to the grid
                        .padding(gridOuterPadding, gridOuterPaddingValue) // Apply reduced outer padding

                        // --- Footer Text ---
                        Text("Make More Memories!")
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
        .animation(.easeInOut(duration: 0.3), value: hasTappedSplash)
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
