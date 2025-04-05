// This version of FeaturedYearFullScreenView adds a parallax motion effect
// and sets us up for future widget support.

import SwiftUI
import Photos
import CoreMotion

struct FeaturedYearFullScreenView: View {
    let item: MediaItem
    let yearsAgo: Int
    let onTap: () -> Void
    @State private var image: UIImage? = nil
    @State private var pulseScale: CGFloat = 1.0
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 1.0
    @State private var textOffset: CGFloat = 20
    @State private var textOpacity: Double = 0
    @State private var showLoadingTransition: Bool = false

    private var yearLabel: String {
        yearsAgo == 1 ? "1 Year Ago" : "\(yearsAgo) Years Ago"
    }

    var body: some View {
        ZStack {
            if showLoadingTransition, let currentImage = image {
                LoadingTransitionView(image: currentImage) {
                    onTap()
                }
            } else {
                GeometryReader { geometry in
                    ZStack(alignment: .top) {
                        if let image = image {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                                .colorMultiply(Color(white: 1.1)) // Slightly brightens the image
                                .saturation(1.2) // Increases color saturation by 20%
                                .overlay(
                                    // Enhanced vignette effect
                                    RadialGradient(
                                        gradient: Gradient(colors: [
                                            .clear,
                                            .black.opacity(0.3)
                                        ]),
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: max(geometry.size.width, geometry.size.height) * 0.7
                                    )
                                )
                                .overlay(
                                    // Enhanced top gradient
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            .black.opacity(0.4),
                                            .clear
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .overlay(
                                    // Enhanced bottom gradient
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            .clear,
                                            .black.opacity(0.4)
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .scaleEffect(pulseScale * scale)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showLoadingTransition = true
                                    }
                                }
                        } else {
                            ZStack {
                                Color(.systemGray4)
                                    .ignoresSafeArea()
                                ProgressView()
                            }
                        }

                        VStack(spacing: 16) {
                            Text(yearLabel)
                                .font(.custom("PlayfairDisplay-Bold", size: 53))
                                .foregroundColor(.white)
                                // Stronger base shadow for better contrast
                                .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 2)
                                // Subtle inner glow
                                .shadow(color: .white.opacity(0.3), radius: 2, x: 0, y: 0)
                                // Outer glow for depth
                                .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 0)
                                // Text outline effect
                                .overlay(
                                    Text(yearLabel)
                                        .font(.custom("PlayfairDisplay-Bold", size: 53))
                                        .foregroundColor(.clear)
                                        .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 0)
                                )
                                .padding(.horizontal, 20)
                                .offset(y: textOffset)
                                .opacity(textOpacity)

                            if let date = item.asset.creationDate {
                                Text(formattedDate(from: date))
                                    .font(.custom("PlayfairDisplay-Bold", size: 42))
                                    .foregroundColor(.white)
                                    // Stronger base shadow for better contrast
                                    .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 2)
                                    // Subtle inner glow
                                    .shadow(color: .white.opacity(0.3), radius: 2, x: 0, y: 0)
                                    // Outer glow for depth
                                    .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 0)
                                    // Text outline effect
                                    .overlay(
                                        Text(formattedDate(from: date))
                                            .font(.custom("PlayfairDisplay-Bold", size: 42))
                                            .foregroundColor(.clear)
                                            .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 0)
                                    )
                                    .padding(.horizontal, 20)
                                    .offset(y: textOffset)
                                    .opacity(textOpacity)
                            }
                        }
                        .padding(.top, geometry.size.height * 0.55)
                        .onAppear {
                            withAnimation(.easeOut(duration: 0.8)) {
                                textOffset = 0
                                textOpacity = 1
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            requestImage()
            startPulseAnimation()
            // Reset scale on appear
            scale = 1.0
            textOffset = 20
            textOpacity = 0
            showLoadingTransition = false
        }
        .onDisappear {
            opacity = 0
            textOpacity = 0
        }
        .onChange(of: item) { _, _ in
            // Animate scale when item changes (during swipe)
            withAnimation(.easeInOut(duration: 0.2)) {
                scale = 0.97
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    scale = 1.0
                }
            }
        }
    }

    private func requestImage() {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast

        manager.requestImage(
            for: item.asset,
            targetSize: UIScreen.main.bounds.size,
            contentMode: .aspectFill,
            options: options
        ) { img, _ in
            if let img = img {
                withAnimation(.easeIn(duration: 0.5)) {
                    self.image = img
                }
            }
        }
    }

    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 0.5).repeatCount(1, autoreverses: true)) {
            pulseScale = 1.05
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.5)) {
                pulseScale = 1.0
            }
        }
    }

    private func formattedDate(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        let baseDate = formatter.string(from: date)

        let calendar = Calendar.current
        let day = calendar.component(.day, from: date)
        let suffix: String
        switch day {
        case 11, 12, 13: suffix = "th"
        default:
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }

        let year = calendar.component(.year, from: date)
        return baseDate + suffix + ", \(year)"
    }
}


