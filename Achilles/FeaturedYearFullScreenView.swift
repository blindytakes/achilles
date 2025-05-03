// Throwbaks/Achilles/Views/FeaturedYearFullScreenView.swift

import SwiftUI
import Photos

// Custom modifier for handwriting animation (Keep existing modifier code)
// ... (HandwritingAnimationModifier and extension remain the same) ...
struct HandwritingAnimationModifier: ViewModifier {
    let active: Bool
    let duration: Double
    let delay: Double
    let yearsAgo: Int
    @ObservedObject var viewModel: PhotoViewModel
    @State private var progress: CGFloat = 0
    @State private var opacity: CGFloat = 0
    @State private var scale: CGFloat = 1.0
    private let fadeInDurationFactor: Double = 0.15
    private let writeOutDelayFactor: Double = 0.5
    private let gradientWidthFactor: CGFloat = 0.15

    func body(content: Content) -> some View {
        content
            .opacity(active ? opacity : 1.0)
            .scaleEffect(active ? scale : 1.0)
            .mask(
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [.black, .clear]),
                                startPoint: .trailing,
                                endPoint: .leading
                            ))
                            .frame(width: geo.size.width * gradientWidthFactor)
                            .offset(x: progress * geo.size.width - geo.size.width * gradientWidthFactor)
                        Rectangle()
                            .fill(Color.black)
                            .frame(width: progress * geo.size.width, height: geo.size.height)
                    }
                }
            )
            .onAppear {
                guard active else { return }
                progress = 0
                opacity = 0
                scale = 1.0
                let fadeInDuration = duration * fadeInDurationFactor
                let writeOutDelay = delay * writeOutDelayFactor
                let writeOutDuration = duration
                withAnimation(.easeIn(duration: fadeInDuration)) { opacity = 1.0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + writeOutDelay) {
                    withAnimation(.easeOut(duration: writeOutDuration)) { progress = 1.0 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + writeOutDuration) {
                        if active {
                            print("⏰ Marking animation completed via modifier for year: \(yearsAgo)")
                            viewModel.markAnimated(yearsAgo: yearsAgo)
                        }
                    }
                }
            }
    }
}

extension View {
    func handwritingAnimation(active: Bool, duration: Double = 1.5, delay: Double = 0.2, yearsAgo: Int, viewModel: PhotoViewModel) -> some View {
        self.modifier(HandwritingAnimationModifier(active: active, duration: duration, delay: delay, yearsAgo: yearsAgo, viewModel: viewModel))
    }
}


// MARK: - Main View Struct
struct FeaturedYearFullScreenView: View {
    // MARK: - Properties
    let item: MediaItem
    let yearsAgo: Int
    let onTap: () -> Void
    let preloadedImage: UIImage?

    @StateObject private var motion = ParallaxMotionManager()
    @ObservedObject var viewModel: PhotoViewModel

    // View state
    @State private var image: UIImage?
    @State private var isLoadingImage: Bool = false
    @State private var showLoadingTransition: Bool = false
    @State private var imageBrightness: Double = -0.1
    @State private var imageScale: CGFloat = 1.05
    // <<< NEW: Task tracking for image loading initiated by this view >>>
    @State private var imageLoadTask: Task<Void, Never>? = nil

    // MARK: - Constants
    // ... (Keep existing constants) ...
    private let yearLabelFontSize: CGFloat = 56
    private let dateLabelFontSize: CGFloat = 50
    private let dateFontName: String = "SnellRoundhand-Bold"
    private let imageLoadFadeDuration: Double = 0.4
    private let handwritingAnimationDuration: Double = 2.0
    private let handwritingAnimationDelay: Double = 0.3
    private let initialImageBrightness: Double = -0.1
    private let targetImageBrightness: Double = 0.08
    private let initialImageScale: CGFloat = 1.05
    private let targetImageScale: CGFloat = 1.0
    private let imageTransitionDuration: Double = 0.3
    private let imageAppearEffectDuration: Double = 1.5
    private let imageAppearEffectDelay: Double = 0.2
    private let imageScaleDuration: Double = 5.0


    // MARK: - Initialization
    init(
        item: MediaItem,
        yearsAgo: Int,
        onTap: @escaping () -> Void,
        viewModel: PhotoViewModel,
        preloadedImage: UIImage? = nil
    ) {
        self.item = item
        self.yearsAgo = yearsAgo
        self.onTap = onTap
        self.viewModel = viewModel
        self.preloadedImage = preloadedImage
        // Initialize state based on preloaded image
        self._image = State(initialValue: preloadedImage)
        self._isLoadingImage = State(initialValue: preloadedImage == nil)
    }


    // MARK: - Computed Properties
    private var yearLabel: String {
        yearsAgo == 1 ? "1 Year Ago" : "\(yearsAgo) Years Ago"
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            // MARK: - Main content branch
            if showLoadingTransition, let currentImage = image {
                // Transition view case
                LoadingTransitionView(image: currentImage, onComplete: onTap)
                    .transition(.opacity)
            } else {
                // Regular view case
                GeometryReader { geometry in
                    ZStack(alignment: .top) {
                        // Background image
                        if let displayImage = image {
                            Image(uiImage: displayImage)
                                // ... (existing image modifiers) ...
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
                                            .black.opacity(0.3), // Use constant
                                            .black.opacity(0.7)  // Use constant
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .ignoresSafeArea()
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: imageTransitionDuration)) {
                                        showLoadingTransition = true
                                    }
                                }
                                .onAppear { // Image Effects Animation
                                    guard viewModel.shouldAnimateImageEffects(yearsAgo: yearsAgo) else {
                                        imageBrightness = targetImageBrightness
                                        imageScale = targetImageScale
                                        print("🖼️ Image effects already done for \(yearsAgo), skipping animation.")
                                        return
                                    }
                                    viewModel.markImageEffectsAnimated(yearsAgo: yearsAgo)
                                    print("🖼️ Performing IMAGE effects animation for \(yearsAgo).")
                                    withAnimation(.easeInOut(duration: imageAppearEffectDuration).delay(imageAppearEffectDelay)) {
                                        imageBrightness = targetImageBrightness
                                    }
                                    withAnimation(.easeOut(duration: imageScaleDuration)) {
                                        imageScale = targetImageScale
                                    }
                                }
                                .contentShape(Rectangle())
                        } else {
                            // Loading placeholder
                            ZStack {
                                Color(.systemGray4).ignoresSafeArea()
                                if isLoadingImage {
                                    ProgressView()
                                }
                            }
                        }

                        // Year text overlay
                        VStack(spacing: 16) { // Use constant
                            // Year label
                            Text(yearLabel)
                                // ... (existing modifiers) ...
                                .font(.system(size: yearLabelFontSize, weight: .bold))
                                .offset(x: motion.xOffset * 0.3, y: motion.yOffset * 0.3) // Use constant factors
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.7), radius: 4, x: 0, y: 2) // Use constants
                                .shadow(color: .white.opacity(0.3), radius: 2, x: 0, y: 0)
                                .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 0)


                            // Date label with animation
                            if let date = item.asset.creationDate {
                                let dateTextView = Text(date.formatMonthDayOrdinalAndYear())
                                    .font(.custom(dateFontName, size: dateLabelFontSize))
                                    // ... (existing modifiers) ...
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(1.0), radius: 2, x: 0, y: 0)
                                    .shadow(color: .black.opacity(0.65), radius: 6, x: 0, y: 2)
                                    .shadow(color: .white.opacity(0.3), radius: 1.8, x: 0, y: 0)
                                    .offset(x: motion.xOffset * 0.5, y: -10 + motion.yOffset * 0.5) // Use constants
                                    .padding(.horizontal, 20) // Use constant


                                if viewModel.shouldAnimate(yearsAgo: yearsAgo) {
                                    dateTextView
                                        .handwritingAnimation(active: true, duration: handwritingAnimationDuration, delay: handwritingAnimationDelay, yearsAgo: yearsAgo, viewModel: viewModel)
                                        .id("year-\(yearsAgo)")
                                } else {
                                    dateTextView
                                }
                            }
                        }
                        .padding(.top, geometry.size.height * 0.55) // Use constant factor
                    }
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            // Set initial visual state
            imageBrightness = initialImageBrightness
            imageScale = initialImageScale

            // --- Conditional Image Loading using ViewModel ---
            if preloadedImage == nil && imageLoadTask == nil { // <<< Check if task is already running
                print("🖼️ FeaturedYearFullScreenView: No preloaded image for \(yearsAgo), starting VM load task...")
                isLoadingImage = true // Ensure loading indicator shows

                // <<< Launch Task to call ViewModel's async function >>>
                imageLoadTask = Task {
                    // Call the async function on the ViewModel
                    let imageData = await viewModel.requestFullImageData(for: item.asset)

                    // Check for cancellation after await
                    guard !Task.isCancelled else {
                        print("🚫 Image load task cancelled after fetch for \(yearsAgo).")
                        // Don't need to set isLoadingImage = false here, onDisappear handles it
                        return
                    }

                    var loadedUIImage: UIImage? = nil
                    if let data = imageData {
                        loadedUIImage = UIImage(data: data) // Attempt to create image
                    }

                    // Update state on main thread
                    await MainActor.run {
                        if let uiImage = loadedUIImage {
                            print("✅ Featured image loaded via VM Task for \(yearsAgo)")
                            withAnimation(.easeIn(duration: imageLoadFadeDuration)) {
                                self.image = uiImage
                            }
                        } else {
                            print("⚠️ Featured image loaded via VM Task returned nil/invalid data for \(yearsAgo)")
                            // Optionally set an error state or leave placeholder
                        }
                        self.isLoadingImage = false // Mark loading as complete
                        self.imageLoadTask = nil // Clear task reference on completion
                    }
                } // End of Task
            } else if preloadedImage != nil {
                print("🖼️ FeaturedYearFullScreenView: Using preloaded image for \(yearsAgo).")
                isLoadingImage = false // Ensure loading is off
            } else {
                 print("🖼️ FeaturedYearFullScreenView: Image load task already running for \(yearsAgo).")
            }
        }
        .onDisappear {
            showLoadingTransition = false
            // <<< Cancel the image loading task if it's running >>>
            if let task = imageLoadTask {
                print("🚫 FeaturedYearFullScreenView disappearing, cancelling image load task for \(yearsAgo).")
                task.cancel()
                imageLoadTask = nil
                // Also reset loading indicator state if task was cancelled mid-load
                if isLoadingImage {
                     isLoadingImage = false
                }
            }
        }
    }

}
