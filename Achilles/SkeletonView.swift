import SwiftUI

/// SkeletonView provides a reusable loading placeholder layout that mimics
/// the structure of LoadedYearContentView and shows gray boxes while data
/// is loading. It uses SwiftUI's native redacted modifier and an optional
/// shimmer effect to indicate a loading state.
///
/// - Featured Placeholder: a square area with invisible "YYYY" text to
///   reserve space for the year label.
/// - Grid Placeholder: a 3x3 grid of squares matching the final layout.
/// - Uses `.redacted(reason: .placeholder)` for macOS/iOS placeholder style.
/// - Can apply `.shimmering()` for an animated highlight (defined below).
/// - Disabled for interactions and fades in/out with `.transition(.opacity)`.
struct SkeletonView: View {
    var body: some View {
        VStack(spacing: 0) {
            // MARK: Featured item placeholder
            Rectangle()
                .fill(Color(.systemGray5))      // Gray box background
                .aspectRatio(1.0, contentMode: .fit)
                .overlay(
                    Text("YYYY")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.clear)     // Invisible text to reserve space
                        .padding(8)
                        .frame(maxWidth: .infinity,
                               maxHeight: .infinity,
                               alignment: .bottom)
                )
                .padding(.bottom, 8)             // Spacing before grid

            // MARK: Grid item placeholders
            VStack(spacing: 5) {
                ForEach(0..<3) { _ in
                    HStack(spacing: 5) {
                        ForEach(0..<3) { _ in
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .aspectRatio(1.0, contentMode: .fit)
                        }
                    }
                }
            }
            .padding(.horizontal, 5)             // Match grid padding

            Spacer()                              // Push content to top
        }
        .padding(.top, 5)                         // Top padding
        .redacted(reason: .placeholder)          // System placeholder styling
        .shimmering()                            // Optional shimmer animation
        .disabled(true)                          // Disable interactions
        .transition(.opacity)                    // Fade in/out transition
    }
}

// MARK: - Shimmering Modifier

/// Applies a left-to-right shimmer animation as an overlay mask.
struct ShimmeringModifier: ViewModifier {
    @State private var phase: CGFloat = -1.0    // Animation progress
    var duration: Double = 1.5                  // Full cycle duration
    var delay: Double = 0.2                     // Delay between loops
    var bounce: Bool = false                    // Reverse direction if true

    func body(content: Content) -> some View {
        content
            .modifier(
                AnimatedMask(phase: phase)
                    .animation(
                        Animation.linear(duration: duration)
                            .delay(delay)
                            .repeatForever(autoreverses: bounce)
                    )
            )
            .onAppear { phase = 1.0 }             // Start the shimmer
    }

    /// Inner animatable mask that moves a gradient stripe across the view
    struct AnimatedMask: AnimatableModifier {
        var phase: CGFloat = 0

        var animatableData: CGFloat {
            get { phase }
            set { phase = newValue }
        }

        func body(content: Content) -> some View {
            content
                .mask(alignment: .leading) {
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: phase - 0.2),
                            .init(color: .black, location: phase),
                            .init(color: .clear, location: phase + 0.2)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
        }
    }
}

extension View {
    /// Convenient shorthand to apply the shimmer effect
    func shimmering(
        duration: Double = 1.5,
        bounce: Bool = false,
        delay: Double = 0.2
    ) -> some View {
        modifier(ShimmeringModifier(duration: duration,
                                    delay: delay,
                                    bounce: bounce))
    }
}

// MARK: - Preview
#if DEBUG
struct SkeletonView_Previews: PreviewProvider {
    static var previews: some View {
        SkeletonView()
            .padding()
            .background(Color(.systemBackground))
            .previewLayout(.sizeThatFits)
    }
}
#endif
