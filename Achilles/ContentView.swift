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
        // Use standard appearance for navigation bar if needed
        // .navigationViewStyle(.stack) // Apply if needed, depends on desired iPad behavior
    }
}

// --- Separate View for the Paged TabView ---
struct PagedYearsView: View {
    @ObservedObject var viewModel: PhotoViewModel
    @Binding var selectedYearsAgo: Int?

    // For custom drag gesture state
    @State private var isAnimating = false // Tracks if swipe animation is active
    @State private var dragOffset: CGFloat = 0 // Current horizontal drag offset

    // MARK: - Constants
    private struct Constants {
        // Animation
        static let transitionDuration: Double = 0.3
        static let animationResetDelay: Double = 0.3

        // Drag Gesture Logic
        static let horizontalDragActivationFactor: CGFloat = 1.2 // How much wider than tall drag must be
        static let significantDragThreshold: CGFloat = 40.0     // Min pixel drag to trigger change
        static let significantVelocityThreshold: CGFloat = 1.0  // Min velocity to trigger change
        static let swipeDirectionThresholdFactor: CGFloat = 0.5 // Horizontal drag must be > 0.5 * vertical drag
        static let minDragVelocityDivider: CGFloat = 1.0        // Avoid division by zero

        // Page Indexing
        static let forwardSwipeDirection: Int = 1 // Index increases (older year)
        static let backwardSwipeDirection: Int = -1 // Index decreases (newer year)
        static let minPageIndex: Int = 0
    }

    var body: some View {
        TabView(selection: $selectedYearsAgo) {
            ForEach(viewModel.availableYearsAgo, id: \.self) { yearsAgo in
                YearPageView(viewModel: viewModel, yearsAgo: yearsAgo)
                    .tag(Optional(yearsAgo)) // Tag must match selection type (Int?)
            }
        }
        .tabViewStyle(
            PageTabViewStyle(indexDisplayMode: .never) // Hide default page dots
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure it fills space
        .animation(.easeInOut(duration: Constants.transitionDuration), value: selectedYearsAgo) // Animate page changes
        // Custom Drag Gesture for Horizontal Swipe Navigation
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Only track drag if horizontal movement dominates
                    if abs(value.translation.width) > abs(value.translation.height) * Constants.horizontalDragActivationFactor {
                        // Avoid interfering with potential vertical gestures within YearPageView
                        // isAnimating = true // Maybe set only onEnded?
                        dragOffset = value.translation.width // Track offset for visual feedback (optional)
                    }
                }
                .onEnded { value in
                    // Calculate velocity and check for significant drag distance
                     // Avoid division by zero or small numbers
                    let dragWidth = max(Constants.minDragVelocityDivider, abs(value.translation.width))
                    let velocity = value.predictedEndTranslation.width / dragWidth
                    let isSignificantDrag = abs(value.translation.width) > Constants.significantDragThreshold
                    let isSignificantVelocity = abs(velocity) > Constants.significantVelocityThreshold
                    let isHorizontalDragDominant = abs(value.translation.width) > abs(value.translation.height) * Constants.swipeDirectionThresholdFactor

                    // Only proceed if swipe meets criteria
                    if (isSignificantDrag || isSignificantVelocity) && isHorizontalDragDominant {

                        // Determine direction: positive width means swipe left (go forward in years)
                        let direction = value.translation.width < 0 ? Constants.forwardSwipeDirection : Constants.backwardSwipeDirection

                        // Find current index and calculate target index
                        if let currentYearsAgo = selectedYearsAgo,
                           let currentIndex = viewModel.availableYearsAgo.firstIndex(of: currentYearsAgo) {

                            let targetIndex = currentIndex + direction

                            // Check if target index is valid
                            if targetIndex >= Constants.minPageIndex && targetIndex < viewModel.availableYearsAgo.count {
                                // Animate the change to the new year
                                withAnimation(.easeInOut(duration: Constants.transitionDuration)) {
                                    selectedYearsAgo = viewModel.availableYearsAgo[targetIndex]
                                }
                            }
                        }
                    }

                    // Reset drag state after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + Constants.animationResetDelay) {
                        // isAnimating = false // Reset if used
                        dragOffset = 0
                    }
                }
        )
        // Trigger prefetching when the selected page changes
        .onChange(of: selectedYearsAgo) { _, newValue in
            if let currentYearsAgo = newValue {
                print("Current page: \(currentYearsAgo) years ago. Triggering prefetch.")
                viewModel.triggerPrefetch(around: currentYearsAgo)
            }
        }
    }
}
