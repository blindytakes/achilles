import SwiftUI
import Photos

struct YearSplashView: View {
    let item: MediaItem
    let yearText: String
    let image: UIImage?
    let onTap: () -> Void

    var body: some View {
        ZStack(alignment: .center) {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.black.opacity(0.6), Color.clear, Color.black.opacity(0.6)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } else {
                Rectangle().fill(Color.gray.opacity(0.3))
            }

            VStack(spacing: 10) {
                Text(yearText)
                    .font(.system(size: 60, weight: .heavy))
                    .foregroundStyle(.ultraThickMaterial)
                    .padding(.horizontal, 24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .ignoresSafeArea()
    }
}

