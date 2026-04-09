// ContentView.swift
//
// Main content view — manages photo authorization, tutorial integration,
// and paged year browsing. Tutorial system lives in Views/Tutorial/.

import SwiftUI
import Photos
import UIKit
import AVKit

// MARK: - Main Content View
struct ContentView: View {
    @Binding var initialSelectedYear: Int?

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
        NavigationStack {
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
                let defaultYear: Int
                if let carouselYear = initialSelectedYear, availableYears.contains(carouselYear) {
                    defaultYear = carouselYear
                } else if availableYears.contains(defaultTargetYear) {
                    defaultYear = defaultTargetYear
                } else {
                    defaultYear = availableYears.first!
                }
                selectedYearsAgo = defaultYear
                debugLog("Setting initial selected year to: \(defaultYear)")
                
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
        .onChange(of: initialSelectedYear) { _, newYear in
            if let year = newYear, viewModel.availableYearsAgo.contains(year) {
                selectedYearsAgo = year
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

// MARK: - Tutorial-Enabled Paged Years View
struct TutorialEnabledPagedYearsView: View {
    @ObservedObject var viewModel: PhotoViewModel
    @Binding var selectedYearsAgo: Int?
    @ObservedObject var tutorialManager: InteractiveTutorialManager
    @EnvironmentObject var authVM: AuthViewModel
    
    private struct Constants {
        static let transitionDuration: Double = 0.3
        static let collagePageTag:    Int = -1
        static let settingsPageTag:   Int = -999
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
            
            CollageView()
                .tag(Optional(Constants.collagePageTag))

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
            if let currentYearsAgo = newValue,
               currentYearsAgo != Constants.settingsPageTag,
               currentYearsAgo != Constants.collagePageTag {
                debugLog("Current page: \(currentYearsAgo) years ago. Triggering prefetch.")
                viewModel.triggerPrefetch(around: currentYearsAgo)

                tutorialManager.actionPerformed(for: .swipeYears)
            }
        }
    }
}

// MARK: - Tutorial-Enabled Year Page View
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
            debugLog("Page for \(yearsAgo) appeared, loading.")
            viewModel.loadPage(yearsAgo: yearsAgo)
            viewModel.triggerPrefetch(around: yearsAgo)
        }
    }
}

// MARK: - Tutorial-Enabled Loaded Year Content
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
    private var allGridItems: [MediaItem] {
        var items = [MediaItem]()
        if let featured = featuredItem { items.append(featured) }
        items.append(contentsOf: gridItems)
        return items
    }
    private var mainExperienceHintText: String? {
        guard tutorialManager.hasCompleted, !tutorialManager.isActive else { return nil }
        return "Swipe left/right between years"
    }
    
    @State private var didAnimateDate = false
    @State private var dateAppeared = false
    @State private var dateBounce = false
    @State private var selectedDetail: MediaItem?
    @Environment(\.heroNamespace) private var heroNamespace
    @Environment(\.heroYear) private var heroYear
    @Environment(\.showCarousel) private var showCarousel
    @State private var gridAppeared = false
    @State private var heroTransitionDone = false
    
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

    private func animateDateHeaderIfNeeded() {
        guard !didAnimateDate else { return }
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
    
    private var gridView: some View {
        ScrollView {
            VStack(spacing: 0) {
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
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(yearsAgo) year\(yearsAgo == 1 ? "" : "s") ago, \(formattedDate)")
                .padding(.bottom, 12)
                .onAppear(perform: animateDateHeaderIfNeeded)
                
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Array(allGridItems.enumerated()), id: \.element.id) { index, item in
                        let isHero = index == 0 && heroYear == yearsAgo
                        let delay = Double(min(index, 8)) * 0.06

                        if isHero, let ns = heroNamespace {
                            // Hero cell: GridItemView loads underneath while the
                            // preloaded image flies in via matchedGeometryEffect.
                            ZStack {
                                GridItemView(viewModel: viewModel, item: item) {
                                    selectedDetail = item
                                    tutorialManager.actionPerformed(for: .tapFeatured)
                                    tutorialManager.actionPerformed(for: .viewDetails)
                                }
                                .aspectRatio(1, contentMode: .fill)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)

                                if !heroTransitionDone,
                                   let heroImg = viewModel.getPreloadedFeaturedImage(for: yearsAgo) {
                                    Image(uiImage: heroImg)
                                        .resizable()
                                        .aspectRatio(1, contentMode: .fill)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                                        .matchedGeometryEffect(
                                            id: "hero-featured-\(yearsAgo)",
                                            in: ns,
                                            isSource: !showCarousel
                                        )
                                        .allowsHitTesting(false)
                                }
                            }
                        } else {
                            GridItemView(viewModel: viewModel, item: item) {
                                selectedDetail = item
                                tutorialManager.actionPerformed(for: .tapFeatured)
                                tutorialManager.actionPerformed(for: .viewDetails)
                            }
                            .aspectRatio(1, contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                            .opacity(gridAppeared ? 1 : 0)
                            .offset(y: gridAppeared ? 0 : 24)
                            .animation(.easeOut(duration: 0.45).delay(delay), value: gridAppeared)
                        }
                    }
                }
                .padding(.horizontal, 6)
                
                Text("Make More Memories!")
                  .font(.headline)
                  .padding(.vertical, 12)
                
                Spacer()
            }
        }
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            gridView

            if let hintText = mainExperienceHintText {
                MainExperienceHintView(
                    text: hintText,
                    showsDirectionalArrows: true
                )
                    .transition(.opacity)
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
        .onAppear {
            // Normal page transition (carousel already gone): start stagger immediately
            if !showCarousel { gridAppeared = true }
        }
        .onChange(of: showCarousel) { _, newValue in
            guard !newValue else { return }
            // Carousel just dismissed — stagger starts after hero animation begins
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                gridAppeared = true
            }
            // Fade out the hero overlay once the matched-geometry animation settles
            if heroYear == yearsAgo {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        heroTransitionDone = true
                    }
                }
            }
        }
    }
}
