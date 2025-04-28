import SwiftUI
import Photos

// Custom modifier for handwriting animation
struct HandwritingAnimationModifier: ViewModifier {
    let active: Bool
    let duration: Double // Total duration for the animation effect
    let delay: Double    // Initial delay before starting
    let yearsAgo: Int
    @ObservedObject var viewModel: PhotoViewModel

    @State private var progress: CGFloat = 0 // 0.0 to 1.0 for mask reveal
    @State private var opacity: CGFloat = 0  // 0.0 to 1.0 for fade-in
    @State private var scale: CGFloat = 1.0  // Used for potential future scaling effects

    // MARK: - Constants (Internal to Modifier)
    private let fadeInDurationFactor: Double = 0.15 // Fade-in takes 15% of total duration
    private let writeOutDelayFactor: Double = 0.5  // Write-out starts after 50% of initial delay
    private let gradientWidthFactor: CGFloat = 0.15 // Width of the mask gradient edge

    func body(content: Content) -> some View {
        content
            .opacity(active ? opacity : 1.0) // Use 1.0 for clarity
            .scaleEffect(active ? scale : 1.0) // Use 1.0 for clarity
            .mask(
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Gradient edge for smoother mask reveal
                        Rectangle()
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [.black, .clear]),
                                startPoint: .trailing,
                                endPoint: .leading
                            ))
                            .frame(width: geo.size.width * gradientWidthFactor) // Use constant
                            .offset(x: progress * geo.size.width - geo.size.width * gradientWidthFactor) // Use constant

                        // Main mask rectangle
                        Rectangle()
                            .fill(Color.black)
                            .frame(width: progress * geo.size.width, height: geo.size.height)
                    }
                }
            )
            .onAppear {
                guard active else { return }
                // Reset state before animating
                progress = 0
                opacity = 0
                scale = 1.0 // Ensure scale starts at 1

                // Calculate internal timings based on factors and passed-in values
                let fadeInDuration = duration * fadeInDurationFactor
                let writeOutDelay = delay * writeOutDelayFactor
                let writeOutDuration = duration // Main write-out animation uses the full duration passed in

                // 1. Fade In
                withAnimation(.easeIn(duration: fadeInDuration)) {
                    opacity = 1.0
                }

                // 2. Write Out (reveal mask) after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + writeOutDelay) {
                    withAnimation(.easeOut(duration: writeOutDuration)) {
                        progress = 1.0
                    }

                    // 3. Mark completion *after* the write-out animation finishes
                    DispatchQueue.main.asyncAfter(deadline: .now() + writeOutDuration) {
                        // Check if still active in case state changed rapidly
                        if active {
                             print("⏰ Marking animation completed via modifier for year: \(yearsAgo)")
                             viewModel.markAnimated(yearsAgo: yearsAgo)
                        }
                    }
                }
            }
    }
}

// Extension to apply the handwriting modifier easily
extension View {
    func handwritingAnimation(active: Bool, duration: Double = 1.5, delay: Double = 0.2, yearsAgo: Int, viewModel: PhotoViewModel) -> some View {
        // Pass default values here if desired, or rely on caller specifying them
        self.modifier(HandwritingAnimationModifier(active: active, duration: duration, delay: delay, yearsAgo: yearsAgo, viewModel: viewModel))
    }
}


// MARK: - Main View Struct
struct FeaturedYearFullScreenView: View {
    // MARK: - Properties
    let item: MediaItem
    let yearsAgo: Int
    let onTap: () -> Void

    @StateObject private var motion = ParallaxMotionManager()
    @ObservedObject var viewModel: PhotoViewModel

    // View state
    @State private var image: UIImage? = nil
    @State private var showLoadingTransition: Bool = false
    @State private var imageBrightness: Double = -0.1 // Initialize with constant value below
    @State private var imageScale: CGFloat = 1.05    // Initialize with constant value below

    // MARK: - Constants
    // Layout & Style
    private let yearLabelFontSize: CGFloat = 56
    private let dateLabelFontSize: CGFloat = 50
    private let dateLabelHorizontalPadding: CGFloat = 20
    private let textOverlayTopPaddingFactor: CGFloat = 0.55
    private let yearLabelParallaxFactor: CGFloat = 0.3
    private let dateLabelParallaxFactor: CGFloat = 0.5
    private let dateLabelVerticalOffset: CGFloat = -10
    private let textOverlaySpacing: CGFloat = 16 // Spacing between Year and Date Text
    private let initialImageBrightness: Double = -0.1
    private let targetImageBrightness: Double = 0.08
    private let initialImageScale: CGFloat = 1.05
    private let targetImageScale: CGFloat = 1.0
    private let textShadowOpacityHigh: Double = 0.7
    private let textShadowRadiusHigh: CGFloat = 4
    private let textShadowYOffsetHigh: CGFloat = 2
    private let textShadowOpacityMedium: Double = 0.3
    private let textShadowRadiusMedium: CGFloat = 2
    private let textShadowOpacityLow: Double = 0.4
    private let textShadowRadiusLow: CGFloat = 6
    private let dateTextShadowOpacityHigh: Double = 1.0
    private let dateTextShadowRadiusHigh: CGFloat = 2
    private let dateTextShadowOpacityMedium: Double = 0.65
    private let dateTextShadowRadiusMedium: CGFloat = 6
    private let dateTextShadowYOffsetMedium: CGFloat = 2
    private let dateTextHighlightOpacity: Double = 0.3
    private let dateTextHighlightRadius: CGFloat = 1.8
    private let backgroundGradientOpacityMedium: Double = 0.3
    private let backgroundGradientOpacityHigh: Double = 0.7
    private let dateFontName: String = "SnellRoundhand-Bold"

    // Animation Timings
    private let imageTransitionDuration: Double = 0.3
    private let imageAppearEffectDuration: Double = 1.5
    private let imageAppearEffectDelay: Double = 0.2
    private let imageScaleDuration: Double = 5.0
    private let imageLoadFadeDuration: Double = 0.4
    private let handwritingAnimationDuration: Double = 2.0
    private let handwritingAnimationDelay: Double = 0.3

    // MARK: - Computed Properties
    private var yearLabel: String {
        yearsAgo == 1 ? "1 Year Ago" : "\(yearsAgo) Years Ago"
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            // MARK: - Main content branch
            if showLoadingTransition, let currentImage = image {
                // MARK: - Transition view case
                LoadingTransitionView(image: currentImage, onComplete: onTap)
                    .transition(.opacity) // Ensure transition view also fades
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
                                            .black.opacity(backgroundGradientOpacityMedium), // Use constant
                                            .black.opacity(backgroundGradientOpacityHigh)  // Use constant
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .ignoresSafeArea()
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: imageTransitionDuration)) { // Use constant
                                        showLoadingTransition = true
                                    }
                                }
                                .onAppear {
                                    // Animate image effects
                                    withAnimation(.easeInOut(duration: imageAppearEffectDuration).delay(imageAppearEffectDelay)) { // Use constants
                                        imageBrightness = targetImageBrightness // Use constant
                                    }
                                    withAnimation(.easeOut(duration: imageScaleDuration)) { // Use constant
                                        imageScale = targetImageScale // Use constant
                                    }
                                }
                                .contentShape(Rectangle())
                        } else {
                            // Loading placeholder
                            ZStack {
                                Color(.systemGray4).ignoresSafeArea() // systemGray4 is fine as literal
                                ProgressView()
                            }
                        }

                        // MARK: - Year text overlay
                        VStack(spacing: textOverlaySpacing) { // Use constant
                            // Year label
                            Text(yearLabel)
                                .font(.system(size: yearLabelFontSize, weight: .bold)) // Use constant
                                .offset(x: motion.xOffset * yearLabelParallaxFactor, y: motion.yOffset * yearLabelParallaxFactor) // Use constant
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(textShadowOpacityHigh), radius: textShadowRadiusHigh, x: 0, y: textShadowYOffsetHigh) // Use constants
                                .shadow(color: .white.opacity(textShadowOpacityMedium), radius: textShadowRadiusMedium, x: 0, y: 0) // Use constants
                                .shadow(color: .black.opacity(textShadowOpacityLow), radius: textShadowRadiusLow, x: 0, y: 0) // Use constants

                            // Date label with animation
                            if let date = item.asset.creationDate {
                                let dateTextView = Text(date.formatMonthDayOrdinalAndYear()) // Use extension method
                                    .font(.custom(dateFontName, size: dateLabelFontSize)) // Use constants
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(dateTextShadowOpacityHigh), radius: dateTextShadowRadiusHigh, x: 0, y: 0) // Use constants
                                    .shadow(color: .black.opacity(dateTextShadowOpacityMedium), radius: dateTextShadowRadiusMedium, x: 0, y: dateTextShadowYOffsetMedium) // Use constants
                                    .shadow(color: .white.opacity(dateTextHighlightOpacity), radius: dateTextHighlightRadius, x: 0, y: 0) // Use constants
                                    .offset(x: motion.xOffset * dateLabelParallaxFactor, y: dateLabelVerticalOffset + motion.yOffset * dateLabelParallaxFactor) // Use constants
                                    .padding(.horizontal, dateLabelHorizontalPadding) // Use constant

                                if viewModel.shouldAnimate(yearsAgo: yearsAgo) {
                                    dateTextView
                                        .handwritingAnimation(active: true, duration: handwritingAnimationDuration, delay: handwritingAnimationDelay, yearsAgo: yearsAgo, viewModel: viewModel) // Use constants
                                        .id("year-\(yearsAgo)") // String interpolation is fine
                                } else {
                                    dateTextView // Apply same modifiers if not animating
                                }
                            }
                        }
                        .padding(.top, geometry.size.height * textOverlayTopPaddingFactor) // Use constant
                    }
                }
                .transition(.opacity) // Add transition for smoother appearance after loading
            }
        }
        .onAppear {
            // Set initial state using constants
            imageBrightness = initialImageBrightness
            imageScale = initialImageScale
            requestImage() // Request image when view appears
        }
        .onDisappear {
            showLoadingTransition = false // Reset transition state
        }
    }

    // MARK: - Image Loading Functions
    private func requestImage() {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none // Request full size
        options.isNetworkAccessAllowed = true
        options.version = .current

        let targetSize = PHImageManagerMaximumSize // System constant is fine

        // Progress handler remains the same...
        options.progressHandler = { progress, error, stop, info in
            if let error = error {
                print("❌ Error loading featured image: \(error.localizedDescription)")
                print("📊 Progress: \(progress)")
                // Retry logic can remain complex, consider simplifying later if needed
                if progress < 1.0 {
                     self.retryWithMaximumQuality()
                 }
            }
        }

        manager.requestImage(
            for: item.asset,
            targetSize: targetSize,
            contentMode: .aspectFill, // Fill the area
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
                        // Use animation constant for fade-in
                        withAnimation(.easeIn(duration: imageLoadFadeDuration)) {
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

    // Retry logic remains largely the same, but uses constant for animation
    private func retryWithMaximumQuality() {
        let manager = PHImageManager.default()
        let retryOptions = PHImageRequestOptions()
        retryOptions.isSynchronous = false
        retryOptions.deliveryMode = .highQualityFormat
        retryOptions.resizeMode = .none
        retryOptions.isNetworkAccessAllowed = true
        retryOptions.version = .current

        manager.requestImage(
            for: item.asset,
            targetSize: PHImageManagerMaximumSize, // System constant
            contentMode: .aspectFill,
            options: retryOptions
        ) { img, info in
            if let img = img {
                Task {
                    await MainActor.run {
                         // Use animation constant for fade-in
                        withAnimation(.easeIn(duration: imageLoadFadeDuration)) {
                            self.image = img
                        }
                    }
                }
            } else {
                print("❌ Maximum quality retry failed")
                // Maybe set an error state here?
            }
        }
    }

    // Removed local formattedDate function - now uses Date extension
}
