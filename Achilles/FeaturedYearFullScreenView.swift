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
    @State private var xTilt: CGFloat = 0
    @State private var yTilt: CGFloat = 0
    private let motionManager = CMMotionManager()

    private var yearLabel: String {
        yearsAgo == 1 ? "1 Year Ago" : "\(yearsAgo) Years Ago"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(x: xTilt, y: yTilt)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.black.opacity(0.6),
                                Color.clear,
                                Color.black.opacity(0.6)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .ignoresSafeArea()
                    .onTapGesture {
                        onTap()
                    }
            } else {
                ZStack {
                    Color(.systemGray4)
                        .ignoresSafeArea()
                    ProgressView()
                }
            }

            VStack(spacing: 10) {
                Text(yearLabel)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(radius: 5)

                if let date = item.asset.creationDate {
                    Text(formattedDate(from: date))
                        .font(.system(size: 32, weight: .medium, design: .serif))
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(radius: 3)
                }
            }
            .padding(.bottom, 60)
        }
        .onAppear {
            requestImage()
            startMotionUpdates()
        }
        .onDisappear {
            motionManager.stopDeviceMotionUpdates()
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
                self.image = img
            }
        }
    }

    private func startMotionUpdates() {
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
            motionManager.startDeviceMotionUpdates(to: .main) { data, _ in
                guard let motion = data else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    self.xTilt = CGFloat(motion.attitude.roll) * 15
                    self.yTilt = CGFloat(motion.attitude.pitch) * 15
                }
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

