import SwiftUI

struct SkeletonView: View {
    var body: some View {
        VStack(spacing: 0) { // Match spacing with LoadedYearContentView if needed later
            // Placeholder for Featured Item Area
            Rectangle()
                .fill(Color(.systemGray5)) // Placeholder color
                .aspectRatio(1.0, contentMode: .fit) // Assume square featured area for now
                .overlay(
                    // Placeholder for Year Indicator Text (optional, helps with layout)
                    Text("YYYY")
                        .font(.system(size: 16, weight: .semibold)) // Example matching font style
                        .foregroundColor(.clear) // Make text invisible but take space
                        .padding(8)
                        .background(.clear)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                )
                .padding(.bottom, 8) // Space between featured and grid (match Loaded view later)

            // Placeholder for Grid Area
            VStack(spacing: 5) { // Match grid spacing
                // Simulate a few rows of grid items
                ForEach(0..<3) { _ in // Example: 3 rows
                    HStack(spacing: 5) { // Match grid spacing
                        ForEach(0..<3) { _ in // Example: 3 columns
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .aspectRatio(1.0, contentMode: .fit)
                        }
                    }
                }
            }
            .padding(.horizontal, 5) // Match grid padding

            Spacer() // Push skeleton content to top
        }
        .padding(.top, 5) // Match grid padding
        .redacted(reason: .placeholder) // Apply redacted modifier to the whole VStack
        .shimmering() // Optional: Add a shimmer effect
        .disabled(true) // Disable interaction on skeleton
        .transition(.opacity) // Add a subtle fade transition
    }
}

// MARK: - Optional Shimmering Effect (Can go in its own file like 'ShimmeringModifier.swift')

struct ShimmeringModifier: ViewModifier {
    @State private var phase: CGFloat = -1.0 // Start off-screen
    var duration: Double = 1.5
    var delay: Double = 0.2 // Add a small delay between repetitions
    var bounce: Bool = false

    func body(content: Content) -> some View {
        content
            .modifier(AnimatedMask(phase: phase).animation(
                Animation.linear(duration: duration)
                    .delay(delay) // Add delay here
                    .repeatForever(autoreverses: bounce)
            ))
            .onAppear { phase = 1.0 } // Animate to the end phase
    }

    // Mask works best on opaque backgrounds
    struct AnimatedMask: AnimatableModifier {
        var phase: CGFloat = 0

        var animatableData: CGFloat {
            get { phase }
            set { phase = newValue }
        }

        func body(content: Content) -> some View {
            content
                .mask(alignment: .leading) { // Align the gradient
                    LinearGradient(gradient: Gradient(stops: [
                        .init(color: .clear, location: phase - 0.2), // Control gradient width/sharpness
                        .init(color: .black, location: phase),
                        .init(color: .clear, location: phase + 0.2),
                    ]), startPoint: .leading, endPoint: .trailing) // Animate left-to-right
                    // Adjust scaleEffect if needed for wider shimmer
                    // .scaleEffect(3)
                }
        }
    }
}

extension View {
    @ViewBuilder func shimmering(duration: Double = 1.5, bounce: Bool = false, delay: Double = 0.2) -> some View {
        modifier(ShimmeringModifier(duration: duration, delay: delay, bounce: bounce))
    }
}

// MARK: - Preview

struct SkeletonView_Previews: PreviewProvider {
    static var previews: some View {
        SkeletonView()
            .padding() // Add padding for preview visibility
            .background(Color.black.opacity(0.1)) // Add background to see shimmer mask
            .previewLayout(.sizeThatFits)
    }
}
