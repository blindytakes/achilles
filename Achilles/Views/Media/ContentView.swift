import SwiftUI
import Photos
import UIKit

// Separated PagedYearsView
struct PagedYearsView: View {
    @ObservedObject var viewModel: PhotoViewModel
    @Binding var selectedYearsAgo: Int?
    @EnvironmentObject var authVM: AuthViewModel
    
    private struct Constants {
        static let transitionDuration: Double = 0.3
        static let settingsPageTag: Int = -999  // Special tag value for Settings page
    }
    
    var body: some View {
        TabView(selection: $selectedYearsAgo) {
            // Year pages
            ForEach(viewModel.availableYearsAgo, id: \.self) { yearsAgo in
                YearPageView(viewModel: viewModel, yearsAgo: yearsAgo)
                    .tag(Optional(yearsAgo))
            }
            
            // Settings page as the last page
            SettingsView(photoViewModel: viewModel)
                .environmentObject(authVM)
                .tag(Optional(Constants.settingsPageTag))
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: Constants.transitionDuration), value: selectedYearsAgo)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: selectedYearsAgo) { _, newValue in
            if let currentYearsAgo = newValue, currentYearsAgo != Constants.settingsPageTag {
                print("Current page: \(currentYearsAgo) years ago. Triggering prefetch.")
                viewModel.triggerPrefetch(around: currentYearsAgo)
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var viewModel: PhotoViewModel // Changed from @StateObject to @EnvironmentObject
    @State private var selectedYearsAgo: Int?

    private let defaultTargetYear: Int = 1

    var body: some View {
        NavigationView {
            contentForAuthorizationStatus
        }
        .onReceive(viewModel.$availableYearsAgo) { availableYears in
            if selectedYearsAgo == nil, !availableYears.isEmpty {
                let defaultYear = availableYears.contains(defaultTargetYear)
                                    ? defaultTargetYear
                                    : availableYears.first!
                selectedYearsAgo = defaultYear
                print("Setting initial selected year to: \(defaultYear)")
            }
        }
    }
    

        @ViewBuilder
        private var contentForAuthorizationStatus: some View {
            switch viewModel.authorizationStatus {
            case .notDetermined:
                AuthorizationRequiredView(
                    status: .notDetermined,
                    onRequest: viewModel.checkAuthorization
                )
                .environmentObject(authVM)
                // Add modifiers for consistency
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground).ignoresSafeArea()) // Optional consistent background
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle("")
                .toolbar(.hidden, for: .navigationBar)

            case .restricted, .denied, .limited:
                AuthorizationRequiredView(
                    status: viewModel.authorizationStatus,
                    onRequest: {} // No action needed here as user must go to Settings
                )
                .environmentObject(authVM)
                // Add modifiers for consistency
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground).ignoresSafeArea()) // Optional consistent background
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle("")
                .toolbar(.hidden, for: .navigationBar)

            case .authorized:
                if viewModel.initialYearScanComplete {
                    // ALWAYS show PagedYearsView if scan is complete and user is authorized.
                    // PagedYearsView will internally handle the case of empty availableYearsAgo
                    // by only showing the Settings page. Its own modifiers will hide the toolbar.
                    PagedYearsView(viewModel: viewModel, selectedYearsAgo: $selectedYearsAgo)
                        .environmentObject(authVM)
                } else {
                    // This is the "Scanning Library..." state, already correctly modified
                    VStack(spacing: 8) {
                        ProgressView("Scanning Library...")
                        Text("Finding relevant years...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground).ignoresSafeArea())
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationTitle("")
                    .toolbar(.hidden, for: .navigationBar)
                }

            @unknown default:
                Text("An unexpected error occurred with permissions.")
                    .foregroundColor(.red)
                // Modify for consistency, or keep title if preferred for errors
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground).ignoresSafeArea()) // Optional consistent background
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle("") // Changed from "Error" to empty for consistency
                .toolbar(.hidden, for: .navigationBar) // Hide toolbar for consistency
            }
        }
    }

// Settings View
struct SettingsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @ObservedObject var photoViewModel: PhotoViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var sumOfPastPhotosOnThisDay: Int? = nil
    @State private var showingDeleteConfirm = false // << NEW STATE VARIABLE

    private let statisticsService = SettingsStatisticsService()

    var body: some View {
        VStack(spacing: 20) { // Main content VStack
            // Account Info Section
            if let user = authVM.user, !user.isAnonymous { // Hide for anonymous users
                VStack(alignment: .leading, spacing: 8) {
                    Text("Account")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text(user.email ?? "No email")
                        .font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
            }

            // "Memories in Numbers" Section
            VStack(alignment: .center, spacing: 10) {
                Text("Memories in Numbers")
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.bold)
                    .padding(.top)
                Text(Date().monthDayWithOrdinalAndYear()) //
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 16)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "calendar.circle.fill")
                            .foregroundColor(.accentColor)
                        Text("# of Years with Photos: \(photoViewModel.availableYearsAgo.count)")
                    }
                    .font(.body)
                    Divider().padding(.horizontal, -8)
                    HStack {
                        Image(systemName: "photo.stack.fill")
                            .foregroundColor(.accentColor)
                        if let totalSum = sumOfPastPhotosOnThisDay {
                            Text("# of Photos on this Day : \(totalSum)")
                        } else {
                            Text("# of Photos on this Day : ")
                            ProgressView()
                        }
                    }
                    .font(.body)
                }
                .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical)
            .background(Color(.systemGray6))
            .cornerRadius(12)

            Button(action: {
                authVM.signOut()
            }) {
                Text("Sign Out")
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
            }

            Spacer() // Pushes Sign Out and Delete Account to the bottom if other content is less

            // << NEW DELETE ACCOUNT BUTTON >>
            if authVM.user?.isAnonymous == false { // Only show for non-anonymous users
                // In Achilles/Views/Media/ContentView.swift, inside SettingsView
                Button(action: {
                    showingDeleteConfirm = true
                }) {
                    Text("Delete Account")
                        .font(.footnote) // You might want to define a font size
                        .foregroundColor(.white)
                        // .frame(maxWidth: .infinity) // << REMOVE THIS LINE or comment it out
                        .padding(.horizontal, 20) // Adjust horizontal padding as needed
                        .padding(.vertical, 10)   // Adjust vertical padding as needed
                        .background(Color.red.opacity(0.3)) // Or use a system color like pink with some opacity
                        .cornerRadius(10)
                }
                .padding(.bottom)
            }
        }
        .padding()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let currentMonthDay = Calendar.current.dateComponents([.month, .day], from: Date())
            Task {
                let sum = await statisticsService.calculateTotalPhotosForCalendarDayFromPastYears(
                    availablePastYearOffsets: photoViewModel.availableYearsAgo,
                    currentMonthDayComponents: currentMonthDay
                ) //
                await MainActor.run {
                    self.sumOfPastPhotosOnThisDay = sum
                }
            }
        }
        // << NEW ALERT FOR DELETE CONFIRMATION >>
        .alert("Delete Account?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await authVM.deleteAccount()
                    // The auth state listener should handle UI changes (e.g., navigating away)
                }
            }
        } message: {
            Text("Are you sure you want to permanently delete your account and all associated data? This action cannot be undone.")
        }
    }
}
