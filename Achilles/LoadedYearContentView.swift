import SwiftUI
import Photos
import CoreLocation // Keep if used elsewhere, not needed for just this view now

struct LoadedYearContentView: View {
    @ObservedObject var viewModel: PhotoViewModel
    let yearsAgo: Int
    let featuredItem: MediaItem?
    let gridItems: [MediaItem]

    @State private var featuredImage: UIImage? = nil
    @State private var selectedItemForDetail: MediaItem? = nil
    // Removed: @State private var locationText: String? = nil (Was for ZoomablePhotoView)

    // 3 Flexible columns with spacing
    let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var actualYear: Int {
        Calendar.current.component(.year, from: Date()) - yearsAgo
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {

                // --- Featured Item Section (Simplified Back to Image) ---
                if let item = featuredItem {
                    ZStack(alignment: .bottom) {
                        // Display Area - Simple Image or Placeholder
                        Group {
                            if let image = featuredImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill() // Fill the frame
                                    .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.width) // Square frame based on screen width
                                    .clipped()
                            } else {
                                Rectangle()
                                    .fill(Color(.systemGray4))
                                    .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.width) // Match frame
                                ProgressView()
                            }
                        }
                        .id(item.id) // Keep ID for potential updates

                        // Video Indicator (Keep)
                        if item.asset.mediaType == .video {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 50, weight: .light))
                                .foregroundColor(.white.opacity(0.9))
                                .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 3)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                                .allowsHitTesting(false) // Don't let icon block taps
                        }

                        // Year Overlay (Keep - Updated Date Formatting)
                        VStack(spacing: 2) {
                            Text("\(yearsAgo) Year\(yearsAgo == 1 ? "" : "s") Ago")
                                .font(.system(size: 48, weight: .bold))
                                .foregroundColor(.white.opacity(0.9))

                            // Use the formattedDate helper if asset date available
                            if let date = item.asset.creationDate {
                                Text(formattedDate(from: date)) // Use helper
                                    .font(.system(size: 38, weight: .bold, design: .serif))
                                    .foregroundColor(.white)
                            } else {
                                // Fallback if date isn't available for some reason
                                Text(String(actualYear))
                                    .font(.system(size: 38, weight: .bold, design: .serif))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .allowsHitTesting(false) // Don't let overlay block taps

                    } // End ZStack
                    .clipped() // Clip the ZStack
                    .onAppear {
                        if featuredImage == nil {
                            requestFeaturedImage(for: item.asset)
                        }
                        // Removed locationText fetching - not needed for simple display
                    }
                    .onTapGesture {
                        // Opens the MediaDetailView sheet
                        selectedItemForDetail = item
                    }
                    .padding(.bottom, 10) // Spacing below featured item

                } else {
                    // Fallback if no featured item
                    Text("Featured item not available.")
                        .padding(.vertical) // Add some padding
                        .padding(.bottom, 8)
                }

                // --- Grid Section (Adjusted Spacing/Padding) ---
                if !gridItems.isEmpty {
                    LazyVGrid(columns: columns, spacing: 2) { // Use matching vertical spacing
                        ForEach(gridItems) { item in
                            GridItemView(viewModel: viewModel, item: item) {
                                selectedItemForDetail = item
                            }
                        }
                    }
                    .padding(.horizontal, 2) // Match horizontal spacing
                } else if featuredItem != nil {
                    // Message if only featured item exists
                    Text("No other items found for this day.")
                        .foregroundColor(.secondary)
                        .padding()
                    Spacer()
                } else {
                    // Spacer if view is completely empty (should be handled by parent view state ideally)
                    Spacer()
                }

            } // End VStack
            .padding(.top, 5) // Padding above featured item/grid
        } // End ScrollView
        .sheet(item: $selectedItemForDetail) { itemToDisplay in
            // Present MediaDetailView when an item is selected
            MediaDetailView(
                viewModel: viewModel,
                // Pass ALL items for the year to the detail view for swiping
                itemsForYear: (featuredItem.map { [$0] } ?? []) + gridItems,
                selectedItemID: itemToDisplay.id
            )
        }
        .onDisappear {
            // Clear selection when this view disappears
             selectedItemForDetail = nil
        }
    }

    // Image loader for featured photo (Unchanged)
    private func requestFeaturedImage(for asset: PHAsset) {
        let targetSize = CGSize(width: 600, height: 600) // Keep reasonable size request
        viewModel.requestImage(for: asset, targetSize: targetSize) { image in
            DispatchQueue.main.async {
                self.featuredImage = image
            }
        }
    }

    // Removed: fetchLocationText function (Was for ZoomablePhotoView)

    // Formatter for Date (Adjust format as desired)
    private func formattedDate(from date: Date) -> String {
        let formatter = DateFormatter()
        // Example format: "MMMM d" (e.g., "April 2")
        // Use "MMMM d, yyyy" if you want the year too, but actualYear is separate
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: date)
    }
}

// Removed: struct ZoomablePhotoView (Use MediaDetailView/ItemDisplayView instead)
