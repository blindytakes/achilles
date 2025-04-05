import SwiftUI
import WidgetKit
import Photos
import CoreMotion

// Custom view modifier to create the drawing animation effect
struct DrawTextModifier: ViewModifier {
    let duration: Double
    let delay: Double
    @State private var progress: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .mask(
                GeometryReader { geometry in
                    Rectangle()
                        .size(width: geometry.size.width * progress, height: geometry.size.height)
                }
            )
            .onAppear {
                withAnimation(.easeOut(duration: duration).delay(delay)) {
                    progress = 1.0
                }
            }
    }
}

extension View {
    func animateDrawing(duration: Double = 1.0, delay: Double = 0.0) -> some View {
        modifier(DrawTextModifier(duration: duration, delay: delay))
    }
}

struct FeaturedYearFullScreenView: View {
    let item: MediaItem
    let yearsAgo: Int
    let onTap: () -> Void
    @State private var image: UIImage? = nil
    @State private var pulseScale: CGFloat = 1.0
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 1.0
    @State private var textOpacity: Double = 0
    @State private var showLoadingTransition: Bool = false
    @State private var showText = false

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
                                .colorMultiply(Color(white: 1.1))
                                .saturation(1.3)
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        .clear,
                                        .black.opacity(0.4)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
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
                                Color(.systemGray4).ignoresSafeArea()
                                ProgressView()
                            }
                        }

                        VStack(spacing: 16) {
                            if showText {
                                Text(yearLabel)
                                    .font(.custom("Georgia-Bold", size: 56))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 2)
                                    .shadow(color: .white.opacity(0.3), radius: 2, x: 0, y: 0)
                                    .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 0)
                                    .overlay(
                                        Text(yearLabel)
                                            .font(.custom("SnellRoundhand-Bold", size: 56))
                                            .foregroundColor(.clear)
                                            .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 0)
                                    )
                                    .padding(.horizontal, 20)
                                    .opacity(textOpacity)

                                if let date = item.asset.creationDate {
                                    Text(formattedDate(from: date))
                                        .font(.custom("SnellRoundhand-Bold", size: 50))
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 2)
                                        .shadow(color: .white.opacity(0.3), radius: 2, x: 0, y: 0)
                                        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 0)
                                        .offset(y: -15)
                                        .overlay(
                                            Text(formattedDate(from: date))
                                                .font(.custom("SnellRoundhand-Bold", size: 45))
                                                .foregroundColor(.clear)
                                                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 0)
                                        )
                                        .padding(.horizontal, 20)
                                        .opacity(textOpacity)
                                        .animateDrawing(duration: 1.1, delay: 0.9)
                                }
                            }
                        }
                        .padding(.top, geometry.size.height * 0.55)
                    }
                }
            }
        }
        .onAppear {
            requestImage()
            startPulseAnimation()
            scale = 1.0
            textOpacity = 0
            showText = false
            showLoadingTransition = false

            withAnimation(.easeIn(duration: 0.5).delay(0.2)) {
                textOpacity = 1
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showText = true
            }
        }
        .onDisappear {
            opacity = 0
            textOpacity = 0
            showText = false
        }
        .onChange(of: item) { _, _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                scale = 0.97
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    scale = 1.0
                }
            }

            textOpacity = 0
            showText = false

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeIn(duration: 0.5)) {
                    textOpacity = 1
                }
                showText = true
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
                    self.image = img // Keep original image for full-screen view
                    self.image = img
                    saveFeaturedPhotoToSharedContainer(image: img)
                }
            }
        }
    }

    private func saveFeaturedPhotoToSharedContainer(image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }

        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.plzwork.Achilles") {
            let fileURL = containerURL.appendingPathComponent("featured.jpg")

            do {
                try data.write(to: fileURL)
                print("✅ Featured photo saved for widget.")

                if let creationDate = item.asset.creationDate {
                    let timestamp = creationDate.timeIntervalSince1970
                    let dateFileURL = containerURL.appendingPathComponent("featured_date.txt")
                    try? "\(timestamp)".write(to: dateFileURL, atomically: true, encoding: .utf8)
                }

                WidgetCenter.shared.reloadAllTimelines()

            } catch {
                print("❌ Error saving image to shared container: \(error)")
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
