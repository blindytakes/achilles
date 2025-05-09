import SwiftUI

// Pulsing animation for UI elements like indicators
struct PulseEffect: ViewModifier {
    @State private var animating = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(animating ? 1.05 : 1.0)
            .opacity(animating ? 0.9 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    animating = true
                }
            }
    }
}

// Extension to make the modifier easier to use
extension View {
    func pulseAnimation() -> some View {
        modifier(PulseEffect())
    }
}

