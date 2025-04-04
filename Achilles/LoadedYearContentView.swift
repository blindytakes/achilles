import SwiftUI
import Photos

struct LoadedYearContentView: View {
    @ObservedObject var viewModel: PhotoViewModel
    let yearsAgo: Int
    let featuredItem: MediaItem?
    let gridItems: [MediaItem]

    @State private var hasTappedSplash = false
    @State private var selectedItemForDetail: MediaItem? = nil

    var allGridItems: [MediaItem] {
        print("--- Calculating allGridItems ---")
        print("hasTappedSplash: \(hasTappedSplash)")
        // VITAL CHECK: Is featuredItem nil or does it have an ID?
        // CORRECTED line:
        print("featuredItem ID: \(featuredItem?.id ?? "nil")")
        print("gridItems count: \(gridItems.count)")

        if hasTappedSplash {
            // This block runs ONLY when the grid should be visible
            if let featured = featuredItem {
                 // This block runs if featuredItem HAS A VALUE
                print(">>> Branch 1: featuredItem is NOT nil. Combining items.")
                let finalItems = [featured] + gridItems
                print("Final combined count: \(finalItems.count)")
                return finalItems
            } else {
                 // This block runs if featuredItem IS NIL
                print(">>> Branch 2: featuredItem IS nil. Returning only gridItems.")
                return gridItems
            }
        } else {
            // This block runs before tapping (when fullscreen view is shown)
            print(">>> Branch 3: hasTappedSplash is false. Returning empty list.")
            return []
        }
    }

    let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        ZStack {
            if let item = featuredItem, !hasTappedSplash {
                FeaturedYearFullScreenView(
                    item: item,
                    yearsAgo: yearsAgo
                ) {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        hasTappedSplash = true
                    }
                }
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        Text("\(yearsAgo) Year\(yearsAgo == 1 ? "" : "s") Ago")
                            .font(.largeTitle.bold())
                            .padding(.top)

                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(allGridItems) { item in
                                GridItemView(viewModel: viewModel, item: item) {
                                    selectedItemForDetail = item
                                }
                            }
                        }
                        .padding(.horizontal, 2)

                        if gridItems.isEmpty {
                            Text("Take More Photos!")
                                .foregroundColor(.secondary)
                                .padding()
                            Spacer()
                        }
                    }
                    .padding(.top, 5)
                }
            }
        }
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

