// ContentView.swift - Complete Replacement with Interactive Tutorial
// This file replaces your existing ContentView.swift entirely

import SwiftUI
import Photos
import UIKit
import AVKit

// MARK: - Enhanced Tutorial Manager
@MainActor
class InteractiveTutorialManager: ObservableObject {
    @Published var currentStep: TutorialStep = .welcome
    @Published var isActive = false
    @Published var showOverlay = false
    @AppStorage("tutorialCurrentStep") private var persistedStep: String = "welcome"
    @AppStorage("hasCompletedInteractiveTutorial") var hasCompleted = false
    
    // Animation states
    @Published var isPulsing = false
    @Published var showArrows = false
    
    enum TutorialStep: String, CaseIterable {
        case welcome
        case swipeYears
        case tapFeatured
        case viewDetails
        case useLocation
        case completed
        
        var title: String {
            switch self {
            case .welcome: return "Welcome to Throwbaks!"
            case .swipeYears: return "Swipe Between Years"
            case .tapFeatured: return "Tap Your Featured Photo"
            case .viewDetails: return "Full Functionality"
            case .useLocation: return "View Photo Locations"
            case .completed: return "Get Ready To Explore!"
            }
        }
        
        var instruction: String {
            switch self {
            case .welcome:
                return "ThrowBaks highlights photos from today's date from previous years"
            case .swipeYears:
                return "Swipe Left to see older years, Swipe Right to see newer years"
            case .tapFeatured:
                return "Tap the Featured Photo to see all photos from that day"
            case .viewDetails:
                return "You can zoom in, view Live Photos, and Share Photos to all your favorite apps"
            case .useLocation:
                return "When you see a map button, tap to see where the photo was taken"
            case .completed:
                return "ThrowBaks is Easy to Use"
            }
        }
        
        var requiresUserAction: Bool {
            switch self {
            case .welcome, .completed: return false
            default: return true
            }
        }
        
        var hasNext: Bool {
            self != .completed
        }
    }
    
    init() {
        if !hasCompleted, let step = TutorialStep(rawValue: persistedStep) {
            currentStep = step
        }
    }
    
    func startTutorial() {
        isActive = true
        showOverlay = true
        currentStep = .welcome
        persistedStep = currentStep.rawValue
        startAnimationsForStep()
    }
    
    func nextStep() {
        guard currentStep.hasNext else {
            completeTutorial()
            return
        }
        
        let allSteps = TutorialStep.allCases
        if let currentIndex = allSteps.firstIndex(of: currentStep),
           currentIndex < allSteps.count - 1 {
            withAnimation(.spring()) {
                currentStep = allSteps[currentIndex + 1]
                persistedStep = currentStep.rawValue
                startAnimationsForStep()
            }
        }
    }
    
    func actionPerformed(for step: TutorialStep) {
        guard currentStep == step && isActive else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.nextStep()
        }
    }
    
    func skipTutorial() {
        completeTutorial()
    }
    
    func skipToNextStep() {
        nextStep()
    }
    
    private func completeTutorial() {
        withAnimation(.easeOut) {
            isActive = false
            showOverlay = false
            hasCompleted = true
            persistedStep = TutorialStep.completed.rawValue
        }
    }
    
    private func startAnimationsForStep() {
        isPulsing = false
        showArrows = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            switch self.currentStep {
            case .swipeYears:
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    self.showArrows = true
                }
            case .tapFeatured:
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    self.isPulsing = true
                }
            default:
                break
            }
        }
    }
    
    func shouldShowStepGuidance(for step: TutorialStep) -> Bool {
        return isActive && currentStep == step
    }
}

// MARK: - Tutorial Overlay View
struct TutorialOverlayView: View {
    @ObservedObject var tutorialManager: InteractiveTutorialManager
    let geometryProxy: GeometryProxy
    let hasPhotosWithLocation: Bool
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    if !tutorialManager.currentStep.requiresUserAction {
                        tutorialManager.nextStep()
                    }
                }
            
            VStack {
                Spacer()
                
                VStack(spacing: 20) {
                    HStack {
                        ForEach(Array(InteractiveTutorialManager.TutorialStep.allCases.enumerated()), id: \.offset) { index, step in
                            Circle()
                                .fill(index <= InteractiveTutorialManager.TutorialStep.allCases.firstIndex(of: tutorialManager.currentStep) ?? 0 ?
                                     Color.white : Color.white.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }
                    
                    Text(tutorialManager.currentStep.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    Text(stepInstructionText)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                    
                    actionButtons
                }
                .padding(30)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .shadow(radius: 20)
                )
                .padding(.horizontal, 20)
                
                Spacer().frame(height: 100)
            }
            
            tutorialHighlights
        }
    }
    
    private var stepInstructionText: String {
        switch tutorialManager.currentStep {
        case .useLocation:
            return hasPhotosWithLocation ?
                tutorialManager.currentStep.instruction :
                "No photos with location data found. Continue exploring to learn more features!"
        default:
            return tutorialManager.currentStep.instruction
        }
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        Button(tutorialManager.currentStep == .completed ? "Take Me to ThrowBaks!" : "Next") {
            tutorialManager.nextStep()
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 10)
        .background(Color.white)
        .foregroundColor(.black)
        .cornerRadius(8)
        .fontWeight(.semibold)
    }
    
    @ViewBuilder
    private var tutorialHighlights: some View {
        switch tutorialManager.currentStep {
        case .swipeYears:
            HStack {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.left.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                        .opacity(tutorialManager.showArrows ? 1.0 : 0.6)
                        .shadow(color: .black.opacity(0.3), radius: 4)
                    
                    Text("Older")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .opacity(tutorialManager.showArrows ? 1.0 : 0.6)
                }
                
                Spacer()
                
                VStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                        .opacity(tutorialManager.showArrows ? 1.0 : 0.6)
                        .shadow(color: .black.opacity(0.3), radius: 4)
                    
                    Text("Newer")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .opacity(tutorialManager.showArrows ? 1.0 : 0.6)
                }
            }
            .padding(.horizontal, 40)
            .position(x: geometryProxy.size.width / 2, y: geometryProxy.size.height / 2)
            
        case .tapFeatured:
            Circle()
                .stroke(Color.white, lineWidth: 3)
                .frame(width: 200, height: 200)
                .opacity(0.8)
                .scaleEffect(tutorialManager.isPulsing ? 1.2 : 1.0)
                .position(x: geometryProxy.size.width / 2, y: geometryProxy.size.height * 0.4)
                .allowsHitTesting(false)
            
        default:
            EmptyView()
        }
    }
}

// MARK: - Main Content View (Your existing structure preserved)
struct ContentView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var viewModel: PhotoViewModel
    @StateObject private var tutorialManager = InteractiveTutorialManager()
    @State private var selectedYearsAgo: Int?

    private let defaultTargetYear: Int = 1
    
    private var hasPhotosWithLocation: Bool {
        for (_, state) in viewModel.pageStateByYear {
            if case .loaded(let featured, let grid) = state {
                let allItems = [featured].compactMap { $0 } + grid
                if allItems.contains(where: { $0.asset.location != nil }) {
                    return true
                }
            }
        }
        return false
    }

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    contentForAuthorizationStatus
                    
                    if tutorialManager.isActive && tutorialManager.showOverlay {
                        TutorialOverlayView(
                            tutorialManager: tutorialManager,
                            geometryProxy: geometry,
                            hasPhotosWithLocation: hasPhotosWithLocation
                        )
                        .transition(.opacity)
                    }
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
                
                if !tutorialManager.hasCompleted && !availableYears.isEmpty && !tutorialManager.isActive {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        guard !self.viewModel.availableYearsAgo.isEmpty else { return }
                        self.tutorialManager.startTutorial()
                    }
                }
            } else if availableYears.isEmpty && tutorialManager.isActive {
                tutorialManager.skipTutorial()
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)

        case .restricted, .denied, .limited:
            AuthorizationRequiredView(
                status: viewModel.authorizationStatus,
                onRequest: {}
            )
            .environmentObject(authVM)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)

        case .authorized:
            if viewModel.initialYearScanComplete {
                TutorialEnabledPagedYearsView(
                    viewModel: viewModel,
                    selectedYearsAgo: $selectedYearsAgo,
                    tutorialManager: tutorialManager
                )
                .environmentObject(authVM)
            } else {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground).ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle("")
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - Tutorial-Enabled Paged Years View (Your existing PagedYearsView enhanced)
struct TutorialEnabledPagedYearsView: View {
    @ObservedObject var viewModel: PhotoViewModel
    @Binding var selectedYearsAgo: Int?
    @ObservedObject var tutorialManager: InteractiveTutorialManager
    @EnvironmentObject var authVM: AuthViewModel
    
    private struct Constants {
        static let transitionDuration: Double = 0.3
        static let settingsPageTag: Int = -999
    }
    
    var body: some View {
        TabView(selection: $selectedYearsAgo) {
            ForEach(viewModel.availableYearsAgo, id: \.self) { yearsAgo in
                TutorialEnabledYearPageView(
                    viewModel: viewModel,
                    yearsAgo: yearsAgo,
                    tutorialManager: tutorialManager
                )
                .tag(Optional(yearsAgo))
            }
            
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
                
                tutorialManager.actionPerformed(for: .swipeYears)
            }
        }
    }
}

// MARK: - Tutorial-Enabled Year Page View (Your existing YearPageView enhanced)
struct TutorialEnabledYearPageView: View {
    @ObservedObject var viewModel: PhotoViewModel
    let yearsAgo: Int
    @ObservedObject var tutorialManager: InteractiveTutorialManager
    
    var body: some View {
        let state = viewModel.pageStateByYear[yearsAgo] ?? .idle
        
        VStack(spacing: 0) {
            switch state {
            case .idle:
                SkeletonView()
                .transition(.opacity.animation(.easeInOut))

            case .loading:
                SkeletonView()
                .transition(.opacity.animation(.easeInOut))

            case .loaded:
                TutorialEnabledLoadedYearContentView(
                    viewModel: viewModel,
                    yearsAgo: yearsAgo,
                    tutorialManager: tutorialManager
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.4)))

            case .empty:
                EmptyYearView()
                .transition(.opacity.animation(.easeInOut(duration: 0.4)))

            case .error(let message):
                ErrorYearView(
                    viewModel: viewModel,
                    yearsAgo: yearsAgo,
                    errorMessage: message
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.4)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear {
            print("➡️ Page for \(yearsAgo) appeared, telling ViewModel to load.")
            viewModel.loadPage(yearsAgo: yearsAgo)
            print("➡️ Page for \(yearsAgo) appeared. Triggering prefetch.")
            viewModel.triggerPrefetch(around: yearsAgo)
        }
    }
}

// MARK: - Tutorial-Enabled Loaded Year Content (Your existing LoadedYearContentView enhanced)
struct TutorialEnabledLoadedYearContentView: View {
    @ObservedObject var viewModel: PhotoViewModel
    let yearsAgo: Int
    @ObservedObject var tutorialManager: InteractiveTutorialManager
    
    private var pageState: PageState {
        viewModel.pageStateByYear[yearsAgo] ?? .idle
    }
    private var featuredItem: MediaItem? {
        if case .loaded(let featured, _) = pageState { return featured }
        return nil
    }
    private var gridItems: [MediaItem] {
        if case .loaded(_, let items) = pageState { return items }
        return []
    }
    private var hasDismissedSplash: Bool {
        viewModel.dismissedSplashForYearsAgo.contains(yearsAgo)
    }
    private var allGridItems: [MediaItem] {
        var items = [MediaItem]()
        if let featured = featuredItem { items.append(featured) }
        items.append(contentsOf: gridItems)
        return items
    }
    
    @State private var didAnimateDate = false
    @State private var dateAppeared = false
    @State private var dateBounce = false
    @State private var selectedDetail: MediaItem?
    
    private let fadeDuration: Double = 1.0
    private let dateSpringResponse: Double = 0.7
    private let dateSpringDamping: Double = 0.9
    private let dateBounceDelay: Double = 0.2
    private let dateBounceEnd: Double = 0.05
    private let dateAppearRotation: Double = -1
    private let dateAppearScale: CGFloat = 0.95
    private let dateBounceScale: CGFloat = 1.02
    
    private var formattedDate: String {
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month, .day], from: Date())
        comps.year = (comps.year ?? 0) - yearsAgo
        guard let past = calendar.date(from: comps) else { return "" }
        return past.monthDayWithOrdinalAndYear()
    }
    
    private let columns = [
        GridItem(.flexible(), spacing: 5),
        GridItem(.flexible(), spacing: 5)
    ]
    
    private var gridView: some View {
        ScrollView {
            VStack(spacing: 0) {
                if hasDismissedSplash {
                    VStack(spacing: 3) {
                        Text("\(yearsAgo) Year\(yearsAgo == 1 ? "" : "s") Ago")
                            .font(.largeTitle.bold())
                            .padding(.top, 16)
                        
                        Text(formattedDate)
                            .font(.system(size: 20, weight: .regular))
                            .scaleEffect(dateAppeared ? (dateBounce ? dateBounceScale : 1) : dateAppearScale)
                            .rotationEffect(dateAppeared ? .zero : .degrees(dateAppearRotation))
                            .animation(.spring(response: dateSpringResponse, dampingFraction: dateSpringDamping),
                                       value: dateAppeared)
                            .animation(.spring(response: dateSpringResponse, dampingFraction: dateSpringDamping),
                                       value: dateBounce)
                    }
                    .padding(.bottom, 12)
                    .onChange(of: hasDismissedSplash) { oldValue, newValue in
                        guard newValue, !didAnimateDate else { return }
                        didAnimateDate = true
                        
                        withAnimation(.spring(
                            response: dateSpringResponse,
                            dampingFraction: dateSpringDamping
                        )) {
                            dateAppeared = true
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + dateBounceDelay) {
                            withAnimation(.spring(
                                response: dateSpringResponse,
                                dampingFraction: dateSpringDamping
                            )) {
                                dateBounce = true
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + dateBounceEnd) {
                                withAnimation(.spring(
                                    response: dateSpringResponse,
                                    dampingFraction: dateSpringDamping
                                )) {
                                    dateBounce = false
                                }
                            }
                        }
                    }
                }
                
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(allGridItems, id: \.id) { item in
                        withAnimation(nil) {
                            GridItemView(viewModel: viewModel, item: item) {
                                selectedDetail = item
                                tutorialManager.actionPerformed(for: .viewDetails)
                            }
                            .aspectRatio(1, contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                        }
                        .transaction { tx in tx.animation = nil }
                    }
                }
                .padding(.horizontal, 6)
                
                if hasDismissedSplash {
                    Text("Make More Memories!")
                      .font(.headline)
                      .padding(.vertical, 12)
                }
                
                Spacer()
            }
            .opacity(hasDismissedSplash ? 1 : 0)
            .animation(nil, value: hasDismissedSplash)
            .transaction { tx in
                tx.animation = nil
                tx.disablesAnimations = true
            }
        }
    }
    
    var body: some View {
        ZStack {
            gridView
            
            if let featured = featuredItem, !hasDismissedSplash {
                FeaturedYearFullScreenView(
                    item: featured,
                    yearsAgo: yearsAgo,
                    onTap: {
                        viewModel.markSplashDismissed(for: yearsAgo)
                        tutorialManager.actionPerformed(for: .tapFeatured)
                    },
                    viewModel: viewModel,
                    preloadedImage: viewModel.getPreloadedFeaturedImage(for: yearsAgo)
                )
                .transition(.opacity)
                .animation(.easeInOut(duration: fadeDuration), value: hasDismissedSplash)
            }
        }
        .sheet(item: $selectedDetail) { item in
            MediaDetailView(
                viewModel: viewModel,
                itemsForYear: allGridItems,
                selectedItemID: item.id,
                yearsAgo: yearsAgo
            )
        }
        .onDisappear { selectedDetail = nil }
    }
}

// MARK: - Settings View (Your existing SettingsView - unchanged)
struct SettingsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @ObservedObject var photoViewModel: PhotoViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var sumOfPastPhotosOnThisDay: Int? = nil
    @State private var showingDeleteConfirm = false

    private let statisticsService = SettingsStatisticsService()

    var body: some View {
        VStack(spacing: 20) {
            if let user = authVM.user, !user.isAnonymous {
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

            VStack(alignment: .center, spacing: 10) {
                Text("Memories in Numbers")
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.bold)
                    .padding(.top)
                Text(Date().monthDayWithOrdinalAndYear())
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

            Spacer()

            if authVM.user?.isAnonymous == false {
                Button(action: {
                    showingDeleteConfirm = true
                }) {
                    Text("Delete Account")
                        .font(.footnote)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.3))
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
                )
                await MainActor.run {
                    self.sumOfPastPhotosOnThisDay = sum
                }
            }
        }
        .alert("Delete Account?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await authVM.deleteAccount()
                }
            }
        } message: {
            Text("Are you sure you want to permanently delete your account and all associated data? This action cannot be undone.")
        }
    }
}
