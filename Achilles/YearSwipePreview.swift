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

