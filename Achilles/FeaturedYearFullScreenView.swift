import SwiftUI
import WidgetKit
import Photos

struct FeaturedYearFullScreenView: View {
    let item: MediaItem
    let yearsAgo: Int
    let onTap: () -> Void
    
    // View state
    @State private var image: UIImage? = nil
    @State private var opacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var showLoadingTransition: Bool = false
    @State private var showText = false
    @State private var triggerAnimation = false

    private var yearLabel: String {
        yearsAgo == 1 ? "1 Year Ago" : "\(yearsAgo) Years Ago"
    }

    var body: some View {
        ZStack {
            // MARK: - Main content branch
            if showLoadingTransition, let currentImage = image {
                // MARK: - Transition view case
                LoadingTransitionView(image: currentImage, onComplete: onTap)
            } else {
                // MARK: - Regular view case
                GeometryReader { geometry in
                    ZStack(alignment: .top) {
                        // MARK: - Background image
                        if let image = image {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                                .overlay(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            .clear,
                                            .clear,
                                            .black.opacity(0.3),
                                            .black.opacity(0.7)
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .ignoresSafeArea()
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showLoadingTransition = true
                                    }
                                }
                                .onAppear {
                                    handleImageAppear()
                                }
                                .contentShape(Rectangle())
                        } else {
                            // Loading placeholder
                            ZStack {
                                Color(.systemGray4).ignoresSafeArea()
                                ProgressView()
                            }
                        }
                        
                        // MARK: - Year text overlay
                        VStack(spacing: 16) {
                            if showText {
                                // Year label
                                Text(yearLabel)
                                    .font(.custom("Georgia-Bold", size: 56))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.7), radius: 4, x: 0, y: 2)
                                    .shadow(color: .white.opacity(0.3), radius: 2, x: 0, y: 0)
                                    .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 0)
                                
                                // Date label with animation
                                if let date = item.asset.creationDate, triggerAnimation {
                                    Text(formattedDate(from: date))
                                        .font(.custom("SnellRoundhand-Bold", size: 50))
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.7), radius: 4, x: 0, y: 2)
                                        .shadow(color: .white.opacity(0.3), radius: 2, x: 0, y: 0)
                                        .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 0)
                                        .offset(y: -10)
                                        .padding(.horizontal, 20)
                                }
                            }
                        }
                        .padding(.top, geometry.size.height * 0.55)
                    }
                }
            }
        }
        .onAppear {
            handleAppear()
        }
        .onDisappear {
            handleDisappear()
        }
        .onChange(of: item) { oldValue, newValue in
            handleItemChange(oldValue, newValue)
        }
    }
    
    // MARK: - Event Handlers
    
    private func handleAppear() {
        requestImage()
        showText = false
        triggerAnimation = false
        showLoadingTransition = false
    }
    
    private func handleDisappear() {
        showText = false
        triggerAnimation = false
    }
    
    private func handleItemChange(_ oldItem: MediaItem, _ newItem: MediaItem) {
        // Simple crossfade instead of scaling
        showText = false
        triggerAnimation = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showText = true
            triggerAnimation = true
        }
    }
    
    private func handleImageAppear() {
        // Simple animation sequence
        withAnimation(.easeIn(duration: 0.3)) {
            showText = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeIn(duration: 0.3)) {
                triggerAnimation = true
            }
        }
    }

    // MARK: - Helper Functions
    
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

