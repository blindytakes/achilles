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
    @EnvironmentObject var authVM: AuthViewModel // <<<< ADD THIS LINE
    @StateObject private var viewModel = PhotoViewModel()
    @State private var selectedYearsAgo: Int?

    // Constant for default year check
    private let defaultTargetYear: Int = 1

    var body: some View {
        NavigationView { // Your existing NavigationView
            Group {
                switch viewModel.authorizationStatus {
                case .notDetermined:
                    AuthorizationRequiredView(
                        status: .notDetermined,
                        onRequest: viewModel.checkAuthorization
                    )
                    .environmentObject(authVM) // Pass down if needed by AuthRequiredView

                case .restricted, .denied, .limited:
                    AuthorizationRequiredView(
                        status: viewModel.authorizationStatus,
                        onRequest: {}
                    )
                    .environmentObject(authVM) // Pass down if needed

                case .authorized:
                    if viewModel.initialYearScanComplete {
                        if viewModel.availableYearsAgo.isEmpty {
                            Text("No past memories found for today's date.")
                                .foregroundColor(.secondary)
                                .navigationTitle("Memories") // Set title for this specific state
                        } else {
                            PagedYearsView(viewModel: viewModel, selectedYearsAgo: $selectedYearsAgo)
                                // .navigationTitle("Memories") // PagedYearsView handles its own title/toolbar hiding
                                // If PagedYearsView or its children need authVM, pass via .environmentObject()
                                // .environmentObject(authVM)
                        }
                    } else {
                        VStack(spacing: 8) {
                            ProgressView("Scanning Library...")
                            Text("Finding relevant years...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .navigationTitle("Memories") // Set title for loading state
                    }

                @unknown default:
                    Text("An unexpected error occurred with permissions.")
                        .foregroundColor(.red)
                        .navigationTitle("Error") // Set title for error state
                }
            }
            // Add the toolbar item to the NavigationView's content (the Group)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { // Or .navigationBarLeading
                    Button("TEMP SIGN OUT") {
                        print("ContentView: TEMP SIGN OUT toolbar button tapped.")
                        authVM.signOut()
                    }
                    .foregroundColor(.red) // Make it stand out
                }
            }
            // If PagedYearsView isn't setting a title, and you want a consistent one
            // for when PagedYearsView is shown, you might need to adjust title logic slightly.
            // PagedYearsView current sets .navigationTitle("") and .toolbar(.hidden, for: .navigationBar)
            // so this toolbar item might only appear if PagedYearsView is NOT visible or if you
            // remove the .toolbar(.hidden) from PagedYearsView.

            // Alternative if PagedYearsView hides the toolbar:
            // You could put the sign-out button directly in PagedYearsView's toolbar,
            // or make ContentView's toolbar always visible.

        } // End of NavigationView
        // This style is good if ContentView itself provides the main navigation structure
        // .navigationViewStyle(.stack) // Uncomment if you prefer a specific style

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

    // MARK: - Constants
    // Constants remain the same as before
    private struct Constants {
        static let transitionDuration: Double = 0.3
    }

    // MARK: - Body
    var body: some View {
        TabView(selection: $selectedYearsAgo) {
            ForEach(viewModel.availableYearsAgo, id: \.self) { yearsAgo in
                YearPageView(viewModel: viewModel, yearsAgo: yearsAgo)
                    .tag(Optional(yearsAgo))
            }
        }
        .tabViewStyle(
            PageTabViewStyle(indexDisplayMode: .never)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: Constants.transitionDuration), value: selectedYearsAgo)
        // Remove conditional logic and always hide the navigation bar
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
       // .toolbar(.hidden, for: .navigationBar) // Always hide
        .onChange(of: selectedYearsAgo) { _, newValue in
            if let currentYearsAgo = newValue {
                print("Current page: \(currentYearsAgo) years ago. Triggering prefetch.")
                viewModel.triggerPrefetch(around: currentYearsAgo)
            }
        }
    }
}
