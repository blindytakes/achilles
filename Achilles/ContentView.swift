import SwiftUI
import Photos // For PHAuthorizationStatus
import UIKit // Needed for UIApplication below

struct ContentView: View {
    @StateObject private var viewModel = PhotoViewModel()
    @State private var selectedYearsAgo: Int?

    var body: some View {
        NavigationView {
            Group {
                switch viewModel.authorizationStatus {
                case .notDetermined:
                    // Pass the checkAuthorization function as the onRequest closure
                    AuthorizationRequiredView(
                        status: .notDetermined,
                        onRequest: { viewModel.checkAuthorization() } // Fix 1: Pass closure
                    )

                case .restricted, .denied, .limited: // Fix 2: Handle .limited here too
                    // Pass the status. For these states, the internal buttons
                    // handle actions (Open Settings, Manage Photos), so the onRequest
                    // closure passed from here can be empty.
                    AuthorizationRequiredView(
                        status: viewModel.authorizationStatus,
                        onRequest: { } // Fix 3: Pass empty closure, viewModel not needed here
                        // NOTE: Make sure the ".limited" case inside AuthorizationRequiredView
                        // uses viewModel.presentLimitedLibraryPicker() if you add that button back.
                        // For now, this call just needs to compile.
                    )

                case .authorized: // Fix 4: Only proceed if fully authorized
                    if viewModel.initialYearScanComplete {
                        if viewModel.availableYearsAgo.isEmpty {
                            Text("No past memories found for today's date.")
                                .foregroundColor(.secondary)
                                .navigationTitle("Memories")
                        } else {
                            PagedYearsView(viewModel: viewModel, selectedYearsAgo: $selectedYearsAgo)
                        }
                    } else {
                        VStack {
                            ProgressView("Scanning Library...")
                            Text("Finding relevant years...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .navigationTitle("Memories")
                    }

                @unknown default:
                    Text("An unexpected error occurred with permissions.")
                }
            }
        }
        .onReceive(viewModel.$availableYearsAgo) { availableYears in
            if selectedYearsAgo == nil, let defaultYear = availableYears.contains(1) ? 1 : availableYears.first {
                selectedYearsAgo = defaultYear
            }
        }
    }
}

// --- Separate View for the Paged TabView ---
// (PagedYearsView remains the same as before)
struct PagedYearsView: View {
    @ObservedObject var viewModel: PhotoViewModel
    @Binding var selectedYearsAgo: Int?

    var body: some View {
        TabView(selection: $selectedYearsAgo) {
            ForEach(viewModel.availableYearsAgo, id: \.self) { yearsAgo in
                YearPageView(viewModel: viewModel, yearsAgo: yearsAgo)
                    .tag(Optional(yearsAgo))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .onChange(of: selectedYearsAgo) { _, newValue in
            if let currentYearsAgo = newValue {
                print("Current page: \(currentYearsAgo) years ago. Triggering prefetch.")
                viewModel.triggerPrefetch(around: currentYearsAgo)
            }
        }
    }
    }
