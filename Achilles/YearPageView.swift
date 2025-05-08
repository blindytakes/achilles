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



