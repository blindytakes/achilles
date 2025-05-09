// YearPageView.swift
//
// This view displays photo content for a specific year in the past.
//
// YearPageView serves as a container that manages different states of content loading
// for a particular year. It coordinates with a central PhotoViewModel to fetch, display,
// and manage photos from the specified number of years ago.
//
// Key features:
// - State management for yearly photo content (idle, loading, loaded, empty, error)
// - Smooth transitions between different loading states with opacity animations
// - Automatic content loading when the view appears
// - Prefetching of adjacent years' content for smoother browsing experience
// - Error handling with retry capabilities
//
// The view reacts to different content states:
// - Shows a skeleton loading view during idle and loading states
// - Displays the loaded content when photos are successfully retrieved
// - Shows an empty state when no photos exist for the specified year
// - Presents appropriate error messages with retry options when loading fails
//
// This approach centralizes state management in the main ViewModel while keeping
// the view focused on presentation logic and user interactions.

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



