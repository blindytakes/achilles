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
    @State private var isAnimating = false
    @State private var dragOffset: CGFloat = 0

    // MARK: - Constants
    // Constants remain the same as before
    private struct Constants {
        static let transitionDuration: Double = 0.3
        static let animationResetDelay: Double = 0.3
        static let horizontalDragActivationFactor: CGFloat = 1.2
        static let significantDragThreshold: CGFloat = 40.0
        static let significantVelocityThreshold: CGFloat = 1.0
        static let swipeDirectionThresholdFactor: CGFloat = 0.5
        static let minDragVelocityDivider: CGFloat = 1.0
        static let forwardSwipeDirection: Int = 1
        static let backwardSwipeDirection: Int = -1
        static let minPageIndex: Int = 0
    }

    // REMOVED isSplashActiveForSelectedPage computed property - no longer needed

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
        // --- MODIFIED ---
        // Remove conditional logic and always hide the navigation bar
        .navigationBarTitleDisplayMode(.inline) // Keep this if desired, but title won't show
        .navigationTitle("") // Set title to empty as it's hidden
        .toolbar(.hidden, for: .navigationBar) // Always hide
        // --- END MODIFIED ---
        .gesture(
            DragGesture()
                .onChanged { value in
                    if abs(value.translation.width) > abs(value.translation.height) * Constants.horizontalDragActivationFactor {
                        dragOffset = value.translation.width
                    }
                }
                .onEnded { value in
                    let dragWidth = max(Constants.minDragVelocityDivider, abs(value.translation.width))
                    let velocity = value.predictedEndTranslation.width / dragWidth
                    let isSignificantDrag = abs(value.translation.width) > Constants.significantDragThreshold
                    let isSignificantVelocity = abs(velocity) > Constants.significantVelocityThreshold
                    let isHorizontalDragDominant = abs(value.translation.width) > abs(value.translation.height) * Constants.swipeDirectionThresholdFactor

                    if (isSignificantDrag || isSignificantVelocity) && isHorizontalDragDominant {
                        let direction = value.translation.width < 0 ? Constants.forwardSwipeDirection : Constants.backwardSwipeDirection
                        if let currentYearsAgo = selectedYearsAgo,
                           let currentIndex = viewModel.availableYearsAgo.firstIndex(of: currentYearsAgo) {
                            let targetIndex = currentIndex + direction
                            if targetIndex >= Constants.minPageIndex && targetIndex < viewModel.availableYearsAgo.count {
                                withAnimation(.easeInOut(duration: Constants.transitionDuration)) {
                                    selectedYearsAgo = viewModel.availableYearsAgo[targetIndex]
                                }
                            }
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + Constants.animationResetDelay) {
                        dragOffset = 0
                    }
                }
        )
        .onChange(of: selectedYearsAgo) { _, newValue in
            if let currentYearsAgo = newValue {
                print("Current page: \(currentYearsAgo) years ago. Triggering prefetch.")
                viewModel.triggerPrefetch(around: currentYearsAgo)
            }
        }
    }
}
