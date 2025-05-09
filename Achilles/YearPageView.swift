import SwiftUI
import Photos

/// YearPageView orchestrates the per-year loading states and displays
/// the appropriate view for each: a skeleton placeholder, loaded content,
/// empty state, or error view. It reads from a shared PhotoViewModel
/// and triggers page load and prefetch on appear.
///
/// Usage:
/// ```swift
/// YearPageView(viewModel: photoViewModel, yearsAgo: 3)
/// ```
struct YearPageView: View {
    // MARK: - Properties
    /// The shared ViewModel containing page states and load logic
    @ObservedObject var viewModel: PhotoViewModel
    /// The offset in years for this page (0 = this year, 1 = last year, etc.)
    let yearsAgo: Int

    var body: some View {
        // Determine current page state or default to .idle
        let state = viewModel.pageStateByYear[yearsAgo] ?? .idle

        VStack(spacing: 0) {
            switch state {
            case .idle, .loading:
                // Show a skeleton placeholder while idle or loading
                SkeletonView()
                    .transition(.opacity.animation(.easeInOut))

            case .loaded:
                // Display the loaded grid and featured content
                LoadedYearContentView(
                    viewModel: viewModel,
                    yearsAgo: yearsAgo
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.4)))

            case .empty:
                // Show empty state when no content is available
                EmptyYearView()
                    .transition(.opacity.animation(.easeInOut(duration: 0.4)))

            case .error(let message):
                // Show error view with retry capability
                ErrorYearView(
                    viewModel: viewModel,
                    yearsAgo: yearsAgo,
                    errorMessage: message
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.4)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear {
            // Trigger initial load and prefetch when this page appears
            print("➡️ Page for \(yearsAgo) appeared, loading data.")
            viewModel.loadPage(yearsAgo: yearsAgo)

            print("➡️ Page for \(yearsAgo) appeared, triggering prefetch.")
            viewModel.triggerPrefetch(around: yearsAgo)
        }
        .onDisappear {
            // Optionally cancel in-flight loads when scrolled off-screen
            // print("⬅️ Page for \(yearsAgo) disappeared, canceling load.")
            // viewModel.cancelLoad(yearsAgo: yearsAgo)
        }
    }
}

#if DEBUG
struct YearPageView_Previews: PreviewProvider {
    static var previews: some View {
        // Provide a real or mock PhotoViewModel for previews
        YearPageView(viewModel: PhotoViewModel(), yearsAgo: 1)
            .frame(width: 300, height: 600)
            .background(Color(.systemBackground))
    }
}
#endif
