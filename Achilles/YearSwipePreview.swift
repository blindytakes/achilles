import SwiftUI

/// YearSwipePreview demonstrates a paged swipe interface for viewing photos from past years.
///
/// - Uses a `TabView` with `PageTabViewStyle` to enable swipe gestures between year pages.
/// - Animates between pages with a spring effect on the `currentIndex` binding.
/// - Leverages `@Namespace` and `matchedGeometryEffect` to smoothly transition year and date labels.
struct YearSwipePreview: View {
    // MARK: - State & Namespace
    /// Tracks the currently visible page index
    @State private var currentIndex: Int = 0
    /// Shared namespace for matched geometry animations
    @Namespace private var animation

    // MARK: - Data
    /// List of "years ago" values to display
    let years: [Int] = [1, 2, 3, 4]

    // MARK: - View Body
    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(years.indices, id: \.self) { index in
                ZStack {
                    // Full-screen black background
                    Color.black.ignoresSafeArea()

                    // Centered circular card with year/date labels
                    VStack(spacing: 20) {
                        Circle()
                            .fill(.ultraThinMaterial)               // Blur material background
                            .frame(width: 220, height: 220)         // Fixed circle size
                            .overlay(
                                VStack(spacing: 8) {
                                    // Year label with matched geometry for transition
                                    Text("\(years[index]) Year\(years[index] > 1 ? "s" : "") Ago")
                                        .font(.system(size: 36, weight: .bold))
                                        .foregroundStyle(.white)
                                        .matchedGeometryEffect(id: "year", in: animation)

                                    // Date label showing exact calendar date
                                    Text("April 3rd, \(Calendar.current.component(.year, from: Date()) - years[index])")
                                        .font(.title3)
                                        .foregroundStyle(.white.opacity(0.85))
                                        .matchedGeometryEffect(id: "date", in: animation)
                                }
                            )
                            .shadow(radius: 10)                     // Drop shadow for depth
                    }
                }
                .tag(index)                                    // Tag for TabView selection
            }
        }
        // Use page style with visible index dots
        .tabViewStyle(.page(indexDisplayMode: .always))
        // Animate transitions when currentIndex changes
        .animation(
            .spring(response: 0.5, dampingFraction: 0.8),
            value: currentIndex
        )
    }
}

#Preview {
    // SwiftUI 4.0 preview syntax
    YearSwipePreview()
}
