import SwiftUI
import Photos

// Custom modifier for handwriting animation
struct HandwritingAnimationModifier: ViewModifier {
    let duration: Double
    let delay: Double
    
    @State private var progress: CGFloat = 0
    @State private var opacity: CGFloat = 0
    @State private var scale: CGFloat = 1.0

    
    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(scale)
            .mask(
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [.black, .clear]),
                                startPoint: .trailing,
                                endPoint: .leading
                            ))
                            .frame(width: geo.size.width * 0.15) // Gradient edge width
                            .offset(x: progress * geo.size.width - geo.size.width * 0.15)
                        
                        Rectangle()
                            .fill(Color.black)
                            .frame(width: progress * geo.size.width, height: geo.size.height)
                    }
                }
            )
            .onAppear {
                // Reset then animate
                progress = 0
                opacity = 0
                
                // First fade in - immediate
                withAnimation(.easeIn(duration: duration * 0.15)) {
                    opacity = 1.0
                }
                
                // Then write out the text - minimal delay
                DispatchQueue.main.asyncAfter(deadline: .now() + delay * 0.5) {
                    withAnimation(.easeOut(duration: duration)) {
                        progress = 1.0
                    }
                    
                }
            }
    }
}

extension View {
    func handwritingAnimation(duration: Double = 1.5, delay: Double = 0.2) -> some View {
        self.modifier(HandwritingAnimationModifier(duration: duration, delay: delay))
    }
}

struct FeaturedYearFullScreenView: View {
    let item: MediaItem
    let yearsAgo: Int
    let onTap: () -> Void
    
    // View state
    @State private var image: UIImage? = nil
    @State private var textOpacity: Double = 0
    @State private var showLoadingTransition: Bool = false
    @State private var showText = false
    @State private var triggerAnimation = false
    @State private var dateAnimationProgress: CGFloat = 0
    @State private var imageBrightness: Double = -0.1
    @State private var imageScale: CGFloat = 1.05

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
                                .brightness(imageBrightness)
                                .scaleEffect(imageScale)
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
                                    
                                    // Animate image effects
                                    withAnimation(.easeInOut(duration: 1.5).delay(0.2)) {
                                        imageBrightness = 0.08
                                    }
                                    withAnimation(.easeOut(duration: 5.0)) {
                                        imageScale = 1.0
                                    }
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
                                    .font(.system(size: 56, weight: .bold))
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
                                        .handwritingAnimation(duration: 2.0, delay: 0.3)
                                        .id("date-\(item.id)") // Ensure animation resets when item changes
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
        // Reset state
        showText = false
        triggerAnimation = false
        
        // Start new animations immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            showText = true
            triggerAnimation = true
        }
    }
    
    private func handleImageAppear() {
        // Start both animations almost immediately
        showText = true
        
        // Trigger the date animation with minimal delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            triggerAnimation = true
        }
    }

    private func requestImage() {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.isNetworkAccessAllowed = true
        options.version = .current
        
        let targetSize = PHImageManagerMaximumSize
        print("📏 Requesting FULL RESOLUTION image")

        options.progressHandler = { progress, error, stop, info in
            if let error = error {
                print("❌ Error loading featured image: \(error.localizedDescription)")
                print("📊 Progress: \(progress)")
                if progress < 1.0 {
                    self.retryWithMaximumQuality()
                }
            }
        }

        manager.requestImage(
            for: item.asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { img, info in
            if let error = info?[PHImageErrorKey] as? Error {
                print("❌ Error loading featured image: \(error.localizedDescription)")
                self.retryWithMaximumQuality()
                return
            }

            if let img = img {
                Task {
                    await MainActor.run {
                        self.image = nil
                        withAnimation(.easeIn(duration: 0.4)) {
                            self.image = img
                        }
                    }
                }
            } else {
                print("⚠️ Featured image was nil, retrying with maximum quality")
                self.retryWithMaximumQuality()
            }
        }
    }

    
    private func retryWithMaximumQuality() {
        let manager = PHImageManager.default()
        let retryOptions = PHImageRequestOptions()
        retryOptions.isSynchronous = false
        retryOptions.deliveryMode = .highQualityFormat
        retryOptions.resizeMode = .none
        retryOptions.isNetworkAccessAllowed = true
        retryOptions.version = .current
        
        // Use maximum size for retry
        manager.requestImage(
            for: item.asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFill,
            options: retryOptions
        ) { img, info in
            if let img = img {
                Task {
                    await MainActor.run {
                        self.image = nil
                        withAnimation(.easeIn(duration: 0.4)) {
                            self.image = img
                        }
                    }
                }
            } else {
                print("❌ Maximum quality retry failed")
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




