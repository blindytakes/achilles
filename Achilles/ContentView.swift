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
        .toolbar(.hidden, for: .navigationBar) // Always hide
        .onChange(of: selectedYearsAgo) { _, newValue in
            if let currentYearsAgo = newValue {
                print("Current page: \(currentYearsAgo) years ago. Triggering prefetch.")
                viewModel.triggerPrefetch(around: currentYearsAgo)
            }
        }
    }
}
