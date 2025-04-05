import SwiftUI

struct LoadingTransitionView: View {
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0
    @State private var gridOpacity: Double = 0.0
    @State private var gridScale: CGFloat = 0.95
    @State private var loadingProgress: CGFloat = 0.0
    
    let image: UIImage
    let onComplete: () -> Void
    
    var body: some View {
        ZStack {
            // Background with blur
            Color.black
                .ignoresSafeArea()
            
            // Featured image fading out
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(scale)
                .opacity(opacity)
                .blur(radius: opacity * 10)
                .ignoresSafeArea()
            
            // Grid preview fading in
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Color.black.opacity(0.8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(gridOpacity)
                    .scaleEffect(gridScale)
                    .ignoresSafeArea()
                
                // Grid loading animation
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.1),
                                Color.white.opacity(0.05),
                                Color.clear
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: UIScreen.main.bounds.height * loadingProgress)
                    .opacity(gridOpacity)
            }
        }
        .onAppear {
            startTransition()
        }
    }
    
    private func startTransition() {
        // First, scale down and fade out the featured image
        withAnimation(.easeInOut(duration: 0.1)) {
            scale = 0.95
            opacity = 0.5
        }
        
        // Then, fade in the grid preview
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeInOut(duration: 0.1)) {
                gridOpacity = 1.0
                gridScale = 1.0
            }
            
            // Start the vertical loading animation
            withAnimation(.easeInOut(duration: 0.15)) {
                loadingProgress = 1.0
            }
        }
        
        // Finally, complete the transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onComplete()
        }
    }
} 
