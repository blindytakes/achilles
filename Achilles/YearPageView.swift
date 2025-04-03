import SwiftUI

struct YearPageView: View {
    @ObservedObject var viewModel: PhotoViewModel
    let yearsAgo: Int

    var body: some View {
        // Get the state for the current year, default to idle if not found yet
        let state = viewModel.pageStateByYear[yearsAgo] ?? .idle

        // Switch over the state to display the correct view
        VStack(spacing: 0) { // Use spacing: 0 if subviews handle their own padding
            switch state {
            case .idle, .loading:
                // Show SkeletonView while loading or before first load attempt
                SkeletonView()

            case .loaded(let featured, let grid):
                // Show the actual content when loaded
                LoadedYearContentView(
                    viewModel: viewModel,
                    yearsAgo: yearsAgo,
                    featuredItem: featured,
                    gridItems: grid
                )

            case .empty:
                // Show the view for when no media was found
                EmptyYearView()

            case .error(let message):
                // Show the error view with a retry option
                ErrorYearView(
                    viewModel: viewModel,
                    yearsAgo: yearsAgo,
                    errorMessage: message
                )
            }
        }
        // Apply modifiers consistently to the VStack or the content views as needed
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure it fills the page
        .clipped()
        .onAppear {
            // Trigger initial load *only if idle*
            // Pre-fetching might already trigger loading, but this ensures it happens
            // if the user lands on a page that wasn't pre-fetched and is still .idle
            if case .idle = state {
                 print("Page for \(yearsAgo) appeared in idle state, triggering load.")
                 Task { await viewModel.loadPage(yearsAgo: yearsAgo) }
            }

            // Always trigger prefetch for adjacent pages when this page appears
            // (ViewModel handles checking if prefetch is actually needed)
            print("Page for \(yearsAgo) appeared. Triggering prefetch.")
            viewModel.triggerPrefetch(around: yearsAgo)
        }
    }
}
