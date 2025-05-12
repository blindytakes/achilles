// FeaturedYearFullScreenView.swift
//
// This view displays a featured photo as a full-screen presentation with animated text overlays
// and visual effects, typically shown when first accessing memories from a specific year.
//
// Key features:
// - Displays a large background image with subtle brightness and scaling animations
// - Presents year and date text with dynamic effects:
//   - Custom "handwriting" animation that reveals the date text
//   - Parallax motion effects on text elements
// - Handles image loading with proper state management:
//   - Supports preloaded images for better performance
//   - Shows loading indicators while waiting for images
//   - Properly cancels image loading tasks when view disappears
// - Provides transition to the detail view via tap gesture
//
// The view coordinates with the parent view model to track animation states
// and prevent unnecessary animations when revisiting previously animated years.
// It includes a custom ViewModifier for the handwriting animation effect.

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
    @State private var transitionOpacity: Double = 1.0 // For transition fade-out animation
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
                // Fix: Remove the duplicate if statement
                ZStack {
                    Color.black
                        .ignoresSafeArea()
                    
                    Image(uiImage: currentImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(transitionOpacity)
                        .ignoresSafeArea()
                }
                .onAppear {
                    // Animate fade to 0
                    withAnimation(.easeOut(duration: 0.2)) {
                        transitionOpacity = 0
                    }
                    
                    // Call the original onTap after the fade
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onTap()
                    }
                }
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
                                    // Reset the fade for consistent animation
                                    transitionOpacity = 1.0
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
                                let dateTextView = Text(date.monthDayWithOrdinalAndYear())
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
        
        .task(id: item.id) { // <<<< KEY CHANGE: Use .task modifier tied to item.id
            if image != nil && preloadedImage != nil { // Already have an image (likely preloaded)
                print("🖼️ FeaturedYearFullScreenView: Using existing or preloaded image for \(yearsAgo). No new load needed in .task.")
                return
            }

            // If image is nil, it means preloadedImage was also nil or we need to load fresh
            if preloadedImage != nil {
                print("🖼️ FeaturedYearFullScreenView: Assigning preloaded image for \(yearsAgo) in .task.")
                self.image = preloadedImage
                 // After assigning preloadedImage, no further loading is needed from this task.
                return
            }

            print("🖼️ FeaturedYearFullScreenView.task: No preloaded image for \(yearsAgo), starting VM load...")
            // Call the async function on the ViewModel
            let imageData = await viewModel.requestFullImageData(for: item.asset)

            // Check for cancellation (SwiftUI's .task handles this if the view disappears or id changes)
            if Task.isCancelled {
                print("🚫 FeaturedYearFullScreenView.task: Image load task cancelled for \(yearsAgo).")
                return
            }

            var loadedUIImage: UIImage? = nil
            if let data = imageData {
                loadedUIImage = UIImage(data: data)
            }

            if let uiImage = loadedUIImage {
                print("✅ FeaturedYearFullScreenView.task: Featured image loaded for \(yearsAgo)")
                withAnimation(.easeIn(duration: imageLoadFadeDuration)) {
                    self.image = uiImage
                }
            } else {
                print("⚠️ FeaturedYearFullScreenView.task: Featured image data returned nil/invalid for \(yearsAgo)")
                // Optionally set an error state or leave placeholder
            }
        }
        
        .onAppear { // This onAppear is now ONLY for non-loading related setup if any
                   // Set initial visual state for effects (if not already handled by image effects onAppear)
                   if image == nil { // Reset if item changed and image is not yet loaded
                       imageBrightness = initialImageBrightness
                       imageScale = initialImageScale
                   }
                   // The original onAppear that called imageLoadTask should be removed or its content moved to the .task modifier
               }
               .onDisappear {
                   showLoadingTransition = false
                   // The .task modifier automatically handles cancellation of the Task when the view disappears or item.id changes.
                   // So, manual cancellation of imageLoadTask is no longer needed here.
                   print("🚫 FeaturedYearFullScreenView disappearing for \(yearsAgo). .task will handle cancellation.")
               }
           }
       }
