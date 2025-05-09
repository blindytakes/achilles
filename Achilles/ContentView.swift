// ContentView.swift
//
// This is the main entry point view for the app, handling photo library authorization
// and displaying the appropriate content based on the current state.
//
// Key features:
// - Manages photo library access permissions with different views for each state:
//   - Request access when permissions aren't determined
//   - Show instructions when access is denied/restricted
//   - Display content when fully authorized
// - Handles the initial photo library scan to find memories from past years
// - Shows appropriate loading states during scanning
// - Provides empty state feedback when no memories are found
// - Includes the PagedYearsView component for navigating between years when memories exist
//
// The view coordinates with PhotoViewModel to handle authorization requests,
// determine available content years, and select a default year (preferring 1 year ago).
// It also manages the navigation UI and paging behavior between different years of memories.


import SwiftUI
import Photos // For PHAuthorizationStatus
import UIKit // Needed for UIApplication below

struct ContentView: View {
    @StateObject private var viewModel = PhotoViewModel()
    @State private var selectedYearsAgo: Int?

    // Constant for default year check
    private let defaultTargetYear: Int = 1

    var body: some View {
        NavigationView {
            Group {
                switch viewModel.authorizationStatus {
                case .notDetermined:
                    // Pass the checkAuthorization function as the onRequest closure
                    AuthorizationRequiredView(
                        status: .notDetermined,
                        onRequest: viewModel.checkAuthorization // Pass function directly
                    )

                case .restricted, .denied, .limited:
                    // Pass the status. Actions are handled internally by AuthorizationRequiredView
                    AuthorizationRequiredView(
                        status: viewModel.authorizationStatus,
                        onRequest: {} // Empty closure needed
                    )

                case .authorized:
                    if viewModel.initialYearScanComplete {
                        if viewModel.availableYearsAgo.isEmpty {
                            // Message when no content found after scan
                            Text("No past memories found for today's date.")
                                .foregroundColor(.secondary)
                                .navigationTitle("Memories") // Keep consistent title
                        } else {
                            // Main content view
                            PagedYearsView(viewModel: viewModel, selectedYearsAgo: $selectedYearsAgo)
                                .navigationTitle("Memories") // Apply title here too
                        }
                    } else {
                        // Loading state while scanning
                        VStack(spacing: 8) { // Add some spacing
                            ProgressView("Scanning Library...")
                            Text("Finding relevant years...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .navigationTitle("Memories") // Keep consistent title
                    }

                @unknown default:
                    Text("An unexpected error occurred with permissions.")
                        .foregroundColor(.red) // Indicate error visually
                        .navigationTitle("Error")
                }
            }
        }
        // Initialize selection once years are available
        .onReceive(viewModel.$availableYearsAgo) { availableYears in
             // Only set default if selection is currently nil AND years are available
             if selectedYearsAgo == nil, !availableYears.isEmpty {
                 // Prefer 1 year ago if available, otherwise first available year
                 let defaultYear = availableYears.contains(defaultTargetYear)
                                     ? defaultTargetYear
                                     : availableYears.first! // Force unwrap safe due to !isEmpty check
                 selectedYearsAgo = defaultYear
                 print("Setting initial selected year to: \(defaultYear)")
             }
         }
    }
}
// --- Separate View for the Paged TabView ---
struct PagedYearsView: View {
    @ObservedObject var viewModel: PhotoViewModel
    @Binding var selectedYearsAgo: Int?

    var body: some View {
        // 1️⃣ Define the TabView and its selection binding
        TabView(selection: $selectedYearsAgo) {
            ForEach(viewModel.availableYearsAgo, id: \.self) { yearsAgo in
                YearPageView(viewModel: viewModel, yearsAgo: yearsAgo)
                    .tag(yearsAgo)
            }
        }
        // 2️⃣ Immediately disable *all* animations on this TabView
        .transaction { tx in
            tx.animation = nil
        }
        // 3️⃣ Then apply your PageTabViewStyle and any other modifiers
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: selectedYearsAgo) { _, newValue in
            if let year = newValue {
                viewModel.triggerPrefetch(around: year)
            }
        }
    }
}

