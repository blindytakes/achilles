// Throwbaks/Achilles/Views/YearPageView.swift
import SwiftUI
import Photos

struct YearPageView: View {
    // Use the ViewModel directly now
    @ObservedObject var viewModel: PhotoViewModel // Renamed from photoViewModel for clarity
    let yearsAgo: Int // Pass yearsAgo explicitly

    // Removed ObservedObject for YearLoader as it's no longer used directly here

    var body: some View {
        // Read the state directly from the main ViewModel's dictionary
        let state = viewModel.pageStateByYear[yearsAgo] ?? .idle // Default to idle if not found

        VStack(spacing: 0) {
            switch state {
            case .idle:
                SkeletonView()
                 .transition(.opacity.animation(.easeInOut)) // Add transition

            case .loading:
                SkeletonView()
                 .transition(.opacity.animation(.easeInOut)) // Add transition

            // <<< CHANGE HERE: Pass only viewModel and yearsAgo >>>
            case .loaded: // We don't need to extract featured/grid here anymore
                LoadedYearContentView(
                    viewModel: viewModel, // Pass the main ViewModel
                    yearsAgo: yearsAgo    // Pass the specific year
                    // featuredItem and gridItems are removed
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.4)))

            case .empty:
                EmptyYearView()
                .transition(.opacity.animation(.easeInOut(duration: 0.4)))

            case .error(let message):
                // Pass the ViewModel and yearsAgo for the retry action
                ErrorYearView(
                    viewModel: viewModel, // Pass the main ViewModel
                    yearsAgo: yearsAgo,
                    errorMessage: message
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.4)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear {
            // Trigger load on the main ViewModel instance
            print("➡️ Page for \(yearsAgo) appeared, telling ViewModel to load.")
            viewModel.loadPage(yearsAgo: yearsAgo) // Call ViewModel's load method

            // Trigger prefetch check on the main ViewModel
            print("➡️ Page for \(yearsAgo) appeared. Triggering prefetch.")
            viewModel.triggerPrefetch(around: yearsAgo)
        }
        .onDisappear {
             // Optional: Cancel load if desired when page scrolls away
             // print("⬅️ Page for \(yearsAgo) disappeared. Cancelling load.")
             // viewModel.cancelLoad(yearsAgo: yearsAgo)
        }
    }
}


// MARK: - Preview Provider (Requires Mock/Dummy Data - Update if needed)
// Note: Previews might need significant updates now that YearLoader is removed
// and YearPageView relies directly on PhotoViewModel state.
// Commenting out for now unless you have mocks ready.
/*
#Preview {
    // Create dummy instances needed by PhotoViewModel
    // ... (Requires MockPhotoLibraryService, MockSelectorService, etc.) ...
    let dummyService = MockPhotoLibraryService()
    let dummySelector = MockSelectorService()
    let dummyFactory = MockMediaItemFactory()
    let dummyCache = ImageCacheService()

    // Create a dummy PhotoViewModel
    let dummyPhotoViewModel = PhotoViewModel(
        service: dummyService,
        selector: dummySelector,
        imageCacheService: dummyCache,
        factory: dummyFactory
    )
    // Set some initial state for preview
    // dummyPhotoViewModel.pageStateByYear[3] = .loaded(featured: /* dummy item */, grid: [/* dummy items */])
    dummyPhotoViewModel.pageStateByYear[3] = .loading // Or .loading, .empty, .error

    // Return the YearPageView with dummy data
    return YearPageView(
        viewModel: dummyPhotoViewModel,
        yearsAgo: 3
    )
    .padding()
    .background(Color.gray.opacity(0.1))
}
*/

