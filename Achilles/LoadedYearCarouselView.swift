// LoadedYearCarouselView.swift
//
// This view presents a swipeable carousel of featured photos from past years.
// Each page in the carousel shows one featured photo from a specific year.
//
// Key features:
// - Uses SwiftUI's TabView with PageTabViewStyle for smooth horizontal swiping
// - Displays each year's featured photo in a full-screen view
// - Each photo has a decorative overlay with a subtle gradient border
// - Tapping any photo navigates to that year's detailed view
// - Provides a fallback view for years with no photos
//
// The carousel is intended as a visual entry point to the app, allowing
// users to quickly browse through memories from different years before
// selecting one to view in more detail.

import SwiftUI
import Photos

struct LoadedYearCarouselView: View {
    let allItemsByYear: [Int: [MediaItem]]
    let onSelectYear: (Int) -> Void
    @ObservedObject var viewModel: PhotoViewModel

    private var sortedYears: [Int] {
        allItemsByYear.keys.sorted()
    }

    var body: some View {
        TabView {
            ForEach(sortedYears, id: \.self) { year in
                if let items = allItemsByYear[year],
                   let featured = viewModel.selector.pickFeaturedItem(from: items) {
                    
                    FeaturedYearFullScreenView(
                        item: featured,
                        yearsAgo: year,
                        onTap: { onSelectYear(year) },
                        viewModel: viewModel
                    )
                    .tag(year)
                    .overlay(
                        RoundedRectangle(cornerRadius: 0)
                            .strokeBorder(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.25),
                                        Color.clear,
                                        Color.white.opacity(0.25)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 4
                            )
                            .blendMode(.overlay)
                    )
                } else {
                    // Fallback for empty or missing data
                    Color.black
                        .overlay(
                            Text("No photos from \(year) years ago")
                                .foregroundColor(.white)
                        )
                        .tag(year)
                }
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .edgesIgnoringSafeArea(.all)
        .background(Color.black)
    }
}

