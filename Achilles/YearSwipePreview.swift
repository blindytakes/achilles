// YearSwipePreview.swift
//
// A horizontal swipeable preview component for browsing through different years.
//
// This view displays an interactive carousel of yearly memory previews,
// showcasing content from various years in the past. Users can swipe
// horizontally to navigate between years.
//
// Key features:
// - Horizontal page-based tab navigation
// - Smooth spring animations for transitions between years
// - Year and date display with matched geometry effects for smooth transitions
// - Consistent styling with glassy materials and subtle shadows
// - Page indicator showing the current position
//
// The view uses TabView with a page style to provide the swipe experience,
// with visual feedback through animations when transitioning between years.
// Each year is represented by a circular container with the year count and
// corresponding date.
//
// The animation namespace ensures smooth transitions between states when
// navigating from this preview to a detailed view.


import SwiftUI

struct YearSwipePreview: View {
    @State private var currentIndex: Int = 0
    @Namespace private var animation

    let years: [Int] = [1, 2, 3, 4]

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(years.indices, id: \.self) { index in
                ZStack {
                    Color.black.ignoresSafeArea()

                    VStack(spacing: 20) {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 220, height: 220)
                            .overlay(
                                VStack(spacing: 8) {
                                    Text("\(years[index]) Year\(years[index] > 1 ? "s" : "") Ago")
                                        .font(.system(size: 36, weight: .bold))
                                        .foregroundStyle(.white)
                                        .matchedGeometryEffect(id: "year", in: animation)

                                    Text("April 3rd, \(Calendar.current.component(.year, from: Date()) - years[index])")
                                        .font(.title3)
                                        .foregroundStyle(.white.opacity(0.85))
                                        .matchedGeometryEffect(id: "date", in: animation)
                                }
                            )
                            .shadow(radius: 10)
                    }
                }
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: currentIndex)
    }
}

#Preview {
    YearSwipePreview()
}

