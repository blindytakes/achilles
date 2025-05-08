// LoadedYearCarouselView.swift
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

