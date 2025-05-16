import SwiftUI
import Photos
import UIKit

struct ContentView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var viewModel = PhotoViewModel()
    @State private var selectedYearsAgo: Int?
    @State private var showingSettings = false

    private let defaultTargetYear: Int = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationView {
                contentForAuthorizationStatus
            }
            
            // Settings button overlay — only when we're on the last (max) year
            if viewModel.authorizationStatus == .authorized,
               let selected = selectedYearsAgo,
               let lastYear = viewModel.availableYearsAgo.max(),
               selected == lastYear
            {
                Button(action: {
                    showingSettings = true
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                        .shadow(radius: 3)
                }
                .padding()
                .sheet(isPresented: $showingSettings) {
                    SettingsView()
                        .environmentObject(authVM)
                }
            }
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

        case .restricted, .denied, .limited:
            AuthorizationRequiredView(
                status: viewModel.authorizationStatus,
                onRequest: {}
            )
            .environmentObject(authVM)

        case .authorized:
            if viewModel.initialYearScanComplete {
                if viewModel.availableYearsAgo.isEmpty {
                    Text("No past memories found for today's date.")
                        .foregroundColor(.secondary)
                        .navigationTitle("Memories")
                } else {
                    PagedYearsView(viewModel: viewModel, selectedYearsAgo: $selectedYearsAgo)
                }
            } else {
                VStack(spacing: 8) {
                    ProgressView("Scanning Library...")
                    Text("Finding relevant years...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .navigationTitle("Memories")
            }

        @unknown default:
            Text("An unexpected error occurred with permissions.")
                .foregroundColor(.red)
                .navigationTitle("Error")
        }
    }
}

// Settings View
struct SettingsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let user = authVM.user {
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
                
                Button(action: {
                    authVM.signOut()
                    dismiss()
                }) {
                    Text("Sign Out")
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// Separated PagedYearsView
struct PagedYearsView: View {
    @ObservedObject var viewModel: PhotoViewModel
    @Binding var selectedYearsAgo: Int?

    private struct Constants {
        static let transitionDuration: Double = 0.3
    }

    var body: some View {
        TabView(selection: $selectedYearsAgo) {
            ForEach(viewModel.availableYearsAgo, id: \.self) { yearsAgo in
                YearPageView(viewModel: viewModel, yearsAgo: yearsAgo)
                    .tag(Optional(yearsAgo))
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: Constants.transitionDuration), value: selectedYearsAgo)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: selectedYearsAgo) { _, newValue in
            if let currentYearsAgo = newValue {
                print("Current page: \(currentYearsAgo) years ago. Triggering prefetch.")
                viewModel.triggerPrefetch(around: currentYearsAgo)
            }
        }
    }
}
