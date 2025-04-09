import SwiftUI

struct LoadingTransitionView: View {
    @State private var opacity: Double = 1.0
    
    let image: UIImage
    let onComplete: () -> Void
    
    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()
            
            // Featured image fading out
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(opacity)
                .ignoresSafeArea()
        }
        .onAppear {
            startTransition()
        }
    }
    
    private func startTransition() {
        // Simple fade out
        withAnimation(.easeOut(duration: 0.2)) {
            opacity = 0
        }
        
        // Complete transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onComplete()
        }
    }
}

