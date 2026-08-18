import SwiftUI
import CoreLocation
import Combine
import Photos
import GoogleMaps3D

struct PlaceRegionCatalog {
    private static let southAmericanCodes: Set<String> = [
        "AR", "BO", "BR", "CL", "CO", "EC", "FK", "GF", "GS", "GY",
        "PE", "PY", "SR", "UY", "VE"
    ]

    static var allCodes: [String] {
        let alpha2Codes = Locale.Region.isoRegions.map(\.identifier).filter { $0.count == 2 }
        return Array(Set(alpha2Codes + ["XK"]))
            .filter { continent(for: $0) != nil }
            .sorted()
    }

    static func continent(for countryCode: String) -> PlaceContinent? {
        let code = countryCode.uppercased()
        if code == "AQ" { return .antarctica }

        let region = Locale.Region(code)
        switch region.continent?.identifier {
        case "002": return .africa
        case "009": return .oceania
        case "019":
            // Locale.Region.subcontinent requires iOS 26. Keep the app's iOS
            // 18 deployment target by explicitly separating the small, stable
            // ISO South America set; all other Americas regions are North America.
            return southAmericanCodes.contains(code) ? .southAmerica : .northAmerica
        case "142": return .asia
        case "150": return .europe
        default: return nil
        }
    }

    static func continentTotals(
        photoCountsByCountryCode: [String: Int]
    ) -> [PlaceContinent: PlaceContinentTotal] {
        var totals: [PlaceContinent: PlaceContinentTotal] = [:]
        for (code, photoCount) in photoCountsByCountryCode where photoCount > 0 {
            guard let continent = continent(for: code) else { continue }
            var total = totals[continent, default: PlaceContinentTotal()]
            total.countryCount += 1
            total.photoCount += photoCount
            totals[continent] = total
        }
        return totals
    }
}

enum PlaceContinent: String, CaseIterable, Identifiable {
    case europe
    case northAmerica
    case southAmerica
    case asia
    case africa
    case oceania
    case antarctica

    var id: String { rawValue }

    var name: String {
        switch self {
        case .europe: return "Europe"
        case .northAmerica: return "North America"
        case .southAmerica: return "South America"
        case .asia: return "Asia"
        case .africa: return "Africa"
        case .oceania: return "Oceania"
        case .antarctica: return "Antarctica"
        }
    }

    fileprivate var cameraTarget: GlobeTarget {
        switch self {
        case .europe:
            return GlobeTarget(source: .continent, coordinate: .init(latitude: 52, longitude: 15), distance: 11_000_000)
        case .northAmerica:
            return GlobeTarget(source: .continent, coordinate: .init(latitude: 38, longitude: -100), distance: 15_000_000)
        case .southAmerica:
            return GlobeTarget(source: .continent, coordinate: .init(latitude: -18, longitude: -60), distance: 13_000_000)
        case .asia:
            return GlobeTarget(source: .continent, coordinate: .init(latitude: 32, longitude: 88), distance: 16_000_000)
        case .africa:
            return GlobeTarget(source: .continent, coordinate: .init(latitude: 3, longitude: 20), distance: 13_000_000)
        case .oceania:
            return GlobeTarget(source: .continent, coordinate: .init(latitude: -24, longitude: 140), distance: 13_000_000)
        case .antarctica:
            return GlobeTarget(source: .continent, coordinate: .init(latitude: -82, longitude: 0), distance: 14_000_000)
        }
    }
}

struct PlaceContinentTotal: Equatable {
    var countryCount = 0
    var photoCount = 0
}

private struct PlaceContinentSummary: Identifiable, Equatable {
    let continent: PlaceContinent
    let countryCount: Int
    let photoCount: Int

    var id: PlaceContinent { continent }
}

private struct ExploreCountry: Identifiable, Equatable {
    let code: String
    let name: String
    let photoCount: Int
    let coordinate: CLLocationCoordinate2D?

    var id: String { code }
    var flag: String {
        code.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }
            .map(String.init).joined()
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.code == rhs.code && lhs.photoCount == rhs.photoCount
    }
}

enum GlobeSelectionSource: String {
    case tap
    case search
    case continent
    case reset
}

struct GlobeTarget: Identifiable {
    let id: UUID
    let countryCode: String?
    let source: GlobeSelectionSource
    let coordinate: CLLocationCoordinate2D
    let distance: CLLocationDistance

    init(
        id: UUID = UUID(),
        countryCode: String? = nil,
        source: GlobeSelectionSource,
        coordinate: CLLocationCoordinate2D,
        distance: CLLocationDistance
    ) {
        self.id = id
        self.countryCode = countryCode?.uppercased()
        self.source = source
        self.coordinate = coordinate
        self.distance = min(63_000_000, max(25_000, distance))
    }

    static var world: GlobeTarget {
        GlobeTarget(
            source: .reset,
            coordinate: CLLocationCoordinate2D(latitude: 14, longitude: 0),
            distance: 35_000_000
        )
    }
}

/// Keeps a selected country above the bottom memory card without exposing
/// layout details to the map SDK. Heading remains north-up, so moving the
/// camera center slightly south places the country in the upper viewport.
enum CountryCameraFraming {
    static func cameraCenter(
        countryCenter: CLLocationCoordinate2D,
        cameraRange: CLLocationDistance
    ) -> CLLocationCoordinate2D {
        let latitudeOffset = min(4, max(0.03, cameraRange / 111_200 * 0.06))
        return CLLocationCoordinate2D(
            latitude: max(-82, min(82, countryCenter.latitude - latitudeOffset)),
            longitude: countryCenter.longitude
        )
    }
}

struct GlobeFlightRequestState {
    private(set) var active: GlobeTarget?
    private(set) var stagedID: UUID?
    private(set) var firedID: UUID?
    private(set) var allowsCorrection = false

    @discardableResult
    mutating func accept(_ request: GlobeTarget?) -> Bool {
        guard let request, request.id != active?.id else { return false }
        active = request
        stagedID = request.id
        allowsCorrection = true
        return true
    }

    /// Called from a view task after SwiftUI has rendered the new destination
    /// camera. A superseded request can never fire an animation.
    @discardableResult
    mutating func markDestinationRendered(_ id: UUID) -> GlobeTarget? {
        guard stagedID == id, active?.id == id else { return nil }
        firedID = id
        return active
    }

    func matchesSelectedCountry(_ selectedCountryCode: String?) -> Bool {
        active?.countryCode == selectedCountryCode?.uppercased()
    }

    /// A completed SDK flight no longer needs the one-shot alignment fallback.
    @discardableResult
    mutating func finishCorrection() -> Bool {
        guard allowsCorrection else { return false }
        allowsCorrection = false
        return true
    }

    mutating func cancel() {
        active = nil
        stagedID = nil
        firedID = nil
        allowsCorrection = false
    }
}

struct GlobeCameraSnapshot {
    let latitude: Double
    let longitude: Double
    let range: CLLocationDistance
}

enum GlobeCameraAlignment {
    static func needsCorrection(
        _ snapshot: GlobeCameraSnapshot,
        for target: GlobeTarget
    ) -> Bool {
        let latitudeError = abs(snapshot.latitude - target.coordinate.latitude)
        let longitudeError = longitudeDistance(
            snapshot.longitude,
            target.coordinate.longitude
        )
        let centerTolerance = min(2, max(0.12, target.distance / 4_000_000))
        let rangeError = abs(snapshot.range - target.distance) / max(target.distance, 1)
        return latitudeError > centerTolerance
            || longitudeError > centerTolerance
            || rangeError > 0.18
    }

    private static func longitudeDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let wrapped = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(wrapped, 360 - wrapped)
    }
}

enum CountryOverviewMarkerVisibilityPolicy {
    private static let earthRadius: CLLocationDistance = 6_371_000

    static func maximumAngularDistance(cameraRange: CLLocationDistance) -> Double {
        min(70, max(12, cameraRange / 35_000_000 * 70))
    }

    static func isVisible(
        coordinate: CLLocationCoordinate2D,
        cameraCenter: CLLocationCoordinate2D,
        cameraRange: CLLocationDistance
    ) -> Bool {
        let distance = CLLocation(
            latitude: cameraCenter.latitude,
            longitude: cameraCenter.longitude
        ).distance(from: CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        ))
        let angularDistance = distance / earthRadius * 180 / .pi
        return angularDistance <= maximumAngularDistance(cameraRange: cameraRange)
    }
}

@MainActor
private final class PlacesViewModel: ObservableObject {
    @Published private(set) var visited: [CountryPhotoSummary] = []
    @Published private(set) var countries: [ExploreCountry] = []
    @Published private(set) var photos: [MediaItem] = []
    @Published private(set) var isIndexing = false
    @Published private(set) var availableYears: [Int] = []
    @Published var selectedCountry: ExploreCountry?
    @Published var selectedYear: Int?
    @Published var globeTarget: GlobeTarget?

    private let indexService: any PhotoIndexServiceProtocol
    private var allSelectedCountryPhotos: [MediaItem] = []
    private var indexObserver: AnyCancellable?
    private var hasRequestedIndex = false

    var totalPhotoCount: Int { visited.reduce(0) { $0 + $1.photoCount } }
    var continentSummaries: [PlaceContinentSummary] {
        let totals = PlaceRegionCatalog.continentTotals(
            photoCountsByCountryCode: Dictionary(
                uniqueKeysWithValues: visited.map { ($0.code, $0.photoCount) }
            )
        )
        return PlaceContinent.allCases.map { continent in
            let total = totals[continent, default: PlaceContinentTotal()]
            return PlaceContinentSummary(
                continent: continent,
                countryCount: total.countryCount,
                photoCount: total.photoCount
            )
        }
    }
    var visitedContinentCount: Int {
        continentSummaries.filter { $0.countryCount > 0 }.count
    }

    init(indexService: any PhotoIndexServiceProtocol = PhotoIndexService.shared) {
        self.indexService = indexService
        isIndexing = !indexService.isIndexReady
        indexObserver = NotificationCenter.default.publisher(
            for: PhotoIndexService.indexDidFinishBuilding
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.refresh() }
        refresh()
    }

    func loadIfNeeded() {
        refresh()
        guard !hasRequestedIndex else { return }
        hasRequestedIndex = true
        // A restored snapshot stays visible while buildIndex performs its
        // inexpensive launch reconciliation in the background.
        isIndexing = !indexService.isIndexReady

        // Entering Places should start its data source immediately instead of
        // waiting for the startup prefetch delay used by the year carousel.
        // This call also checks for photos added while the app was closed.
        let indexService = indexService
        Task(priority: .userInitiated) {
            await indexService.buildIndex()
        }
    }

    func refresh() {
        isIndexing = !indexService.isIndexReady
        visited = indexService.countryPhotoSummaries(locale: .current)
        let visitedByCode = Dictionary(uniqueKeysWithValues: visited.map { ($0.code, $0) })
        countries = PlaceRegionCatalog.allCodes.map { code in
            let summary = visitedByCode[code]
            return ExploreCountry(
                code: code,
                name: Locale.current.localizedString(forRegionCode: code) ?? code,
                photoCount: summary?.photoCount ?? 0,
                coordinate: summary?.coordinate
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        if let current = selectedCountry,
           let refreshed = countries.first(where: { $0.code == current.code }) {
            applySelection(refreshed)
        }
    }

    func select(_ country: ExploreCountry, focusGlobe: Bool = true) {
        UISelectionFeedbackGenerator().selectionChanged()
        if selectedCountry?.code != country.code { selectedYear = nil }
        applySelection(country)
        guard focusGlobe else { return }
        requestCountryFlight(code: country.code, source: .search)
    }

    func selectCountry(code: String) {
        let normalized = code.uppercased()
        guard let country = countries.first(where: { $0.code == normalized }) else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        if selectedCountry?.code != normalized { selectedYear = nil }
        applySelection(country)
        requestCountryFlight(code: normalized, source: .tap)
    }

    func dismissCountryKeepingCamera() {
        selectedCountry = nil
        photos = []
        allSelectedCountryPhotos = []
        availableYears = []
        selectedYear = nil
        globeTarget = nil
    }

    func resetGlobe() {
        selectedCountry = nil
        photos = []
        allSelectedCountryPhotos = []
        availableYears = []
        selectedYear = nil
        globeTarget = .world
    }

    func focus(on continent: PlaceContinent) {
        UISelectionFeedbackGenerator().selectionChanged()
        selectedCountry = nil
        photos = []
        allSelectedCountryPhotos = []
        availableYears = []
        selectedYear = nil
        globeTarget = continent.cameraTarget
    }

    func setYearFilter(_ year: Int?) {
        selectedYear = year
        applyPhotoFilter()
    }

    private func requestCountryFlight(
        code: String,
        source: GlobeSelectionSource
    ) {
        let normalized = code.uppercased()
        guard selectedCountry?.code == normalized else {
#if DEBUG
            assertionFailure("Places refused a camera request that did not match the selected country")
#endif
            return
        }
        let boundaries = CountryBoundaryDataset.shared
        let distance = boundaries.suggestedCameraRange(for: normalized)
        guard let countryCenter = boundaries.representativeCoordinate(for: normalized) else { return }
        let coordinate = CountryCameraFraming.cameraCenter(
            countryCenter: countryCenter,
            cameraRange: distance
        )
        let request = GlobeTarget(
            countryCode: normalized,
            source: source,
            coordinate: coordinate,
            distance: distance
        )
#if DEBUG
        print(
            "🌍 Places request \(request.id.uuidString) source=\(source.rawValue) "
                + "selected=\(normalized) target="
                + "\(String(format: "%.2f", coordinate.latitude)),"
                + "\(String(format: "%.2f", coordinate.longitude)) range=\(Int(request.distance))"
        )
#endif
        globeTarget = request
    }

    private func applySelection(_ country: ExploreCountry) {
        selectedCountry = country
        allSelectedCountryPhotos = indexService.items(forCountryCode: country.code)
        availableYears = Array(Set(allSelectedCountryPhotos.compactMap {
            $0.asset.creationDate.map { Calendar.current.component(.year, from: $0) }
        })).sorted(by: >)
        if let selectedYear, !availableYears.contains(selectedYear) {
            self.selectedYear = nil
        }
        applyPhotoFilter()
    }

    private func applyPhotoFilter() {
        if let selectedYear {
            photos = allSelectedCountryPhotos.filter {
                guard let date = $0.asset.creationDate else { return false }
                return Calendar.current.component(.year, from: date) == selectedYear
            }
        } else {
            photos = allSelectedCountryPhotos
        }
    }
}

struct PlacesView: View {
    @ObservedObject var photoViewModel: PhotoViewModel
    var onNavigateToMemories: (() -> Void)? = nil
    var onNavigateToCreate: (() -> Void)? = nil
    @StateObject private var viewModel = PlacesViewModel()
    @State private var showsCountryPicker = false
    @State private var showsMemories = false
    @State private var showsWorldSummary = false
    @State private var showsLegend = false
    @State private var isAwayFromWorld = false
    @State private var showsDashboardDiscoveryHint = false
    @AppStorage("Places.showMemoryLocations") private var showsCountryPins = true
    @AppStorage("Places.hasCompletedGlobeOnboarding") private var hasCompletedGlobeOnboarding = false
    @AppStorage("Places.hasSeenWorldDashboardHintV3") private var hasSeenWorldDashboardHint = false

    var body: some View {
        ZStack {
            GooglePlacesGlobeView(
                visited: viewModel.visited,
                selectedCode: viewModel.selectedCountry?.code,
                showsCountryPins: showsCountryPins,
                target: viewModel.globeTarget,
                onCountrySelected: { code in
                    hasCompletedGlobeOnboarding = true
                    viewModel.selectCountry(code: code)
                },
                onWorldViewStateChanged: { isAwayFromWorld = $0 }
            )
            .ignoresSafeArea()
            .accessibilityLabel("Interactive world globe with visible country borders")

            LinearGradient(
                colors: [Color.black.opacity(0.3), .clear, Color.black.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0.72), Color.black.opacity(0.34), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 190)
                Spacer(minLength: 0)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            RadialGradient(
                colors: [.clear, Color.black.opacity(0.28)],
                center: .center,
                startRadius: 120,
                endRadius: 460
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                welcomeHeader
                if showsDashboardDiscoveryHint {
                    dashboardDiscoveryHint
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if photoViewModel.authorizationStatus == .limited {
                    limitedLibraryBanner
                }
                Spacer()
                if shouldShowStatusHint {
                    statusHint
                }
                if let country = viewModel.selectedCountry {
                    countryCard(country)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if onNavigateToMemories != nil,
                          onNavigateToCreate != nil {
                    placesNavigationBar
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 18)

        }
        .background(Color(red: 0.03, green: 0.09, blue: 0.14))
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: viewModel.selectedCountry?.code)
        .animation(.easeOut(duration: 0.22), value: showsDashboardDiscoveryHint)
        .sheet(isPresented: $showsCountryPicker) {
            CountryPickerView(countries: viewModel.countries) { country in
                showsCountryPicker = false
                viewModel.select(country)
            }
        }
        .sheet(isPresented: $showsMemories) {
            if let country = viewModel.selectedCountry {
                CountryMemoriesView(
                    photoViewModel: photoViewModel,
                    country: country,
                    photos: viewModel.photos,
                    countries: viewModel.countries
                )
            }
        }
        .sheet(isPresented: $showsWorldSummary) {
            WorldSummarySheet(
                countryCount: viewModel.visited.count,
                continentCount: viewModel.visitedContinentCount,
                photoCount: viewModel.totalPhotoCount,
                summaries: viewModel.continentSummaries,
                visitedCountries: viewModel.countries.filter { $0.photoCount > 0 }
            ) { continent in
                showsWorldSummary = false
                viewModel.focus(on: continent)
            } onCountrySelect: { country in
                showsWorldSummary = false
                viewModel.select(country)
            }
        }
        .sheet(isPresented: $showsLegend) {
            GlobeLegendSheet(showsCountryPins: $showsCountryPins)
        }
        .onAppear {
            viewModel.loadIfNeeded()
            showDashboardDiscoveryHintIfNeeded()
            AnalyticsService.shared.logScreenView("places", screenClass: "PlacesView")
        }
    }

    private var welcomeHeader: some View {
        ZStack(alignment: .top) {
            HStack {
                Button {
                    showsCountryPicker = true
                } label: {
                    headerCircleIcon(systemName: "magnifyingglass")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search all places")

                Spacer()

                Menu {
                    Button {
                        openWorldDashboard()
                    } label: {
                        Label("Travel Dashboard", systemImage: "rectangle.grid.2x2.fill")
                    }
                    .disabled(viewModel.isIndexing && viewModel.visited.isEmpty)

                    Divider()

                    Button {
                        showsLegend = true
                    } label: {
                        Label("About the Globe", systemImage: "info.circle")
                    }

                    Button {
                        showsCountryPins.toggle()
                    } label: {
                        Label(
                            showsCountryPins ? "Hide Country Pins" : "Show Country Pins",
                            systemImage: showsCountryPins ? "eye.slash" : "eye"
                        )
                    }

                    ShareLink(item: worldShareSummary) {
                        Label("Share Your World", systemImage: "square.and.arrow.up")
                    }

                    if canReturnToWorld {
                        Divider()
                        Button {
                            viewModel.resetGlobe()
                        } label: {
                            Label("Return to World", systemImage: "globe.americas.fill")
                        }
                    }
                } label: {
                    headerCircleIcon(systemName: "ellipsis")
                }
                .accessibilityLabel("More globe options")
            }

            Button {
                openWorldDashboard()
            } label: {
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Your World, Mapped")
                            .font(.system(size: 27, weight: .bold))
                            .tracking(-0.4)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if !viewModel.isIndexing || !viewModel.visited.isEmpty {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white.opacity(0.76))
                                .offset(y: 1)
                        }
                    }

                    Text(summaryText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .padding(.top, 52)
            .buttonStyle(WorldDashboardHeaderButtonStyle())
            .disabled(viewModel.isIndexing && viewModel.visited.isEmpty)
            .accessibilityLabel("Open travel dashboard. \(summaryText)")
            .accessibilityHint("Shows your travel statistics and visited places")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 112)
    }

    private var dashboardDiscoveryHint: some View {
        Button {
            openWorldDashboard()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .bold))
                Text("Tap for dashboard")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.11), lineWidth: 1))
            .environment(\.colorScheme, .dark)
            .shadow(color: .black.opacity(0.24), radius: 7, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open travel dashboard")
    }

    private func showDashboardDiscoveryHintIfNeeded() {
        guard !hasSeenWorldDashboardHint else { return }
        hasSeenWorldDashboardHint = true
        showsDashboardDiscoveryHint = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation(.easeOut(duration: 0.22)) {
                showsDashboardDiscoveryHint = false
            }
        }
    }

    private func openWorldDashboard() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        showsDashboardDiscoveryHint = false
        showsWorldSummary = true
    }

    private var canReturnToWorld: Bool {
        viewModel.selectedCountry != nil
            || isAwayFromWorld
            || viewModel.globeTarget?.source == .continent
    }

    private var summaryText: String {
        let countries = viewModel.visited.count
        let continents = viewModel.visitedContinentCount
        if viewModel.isIndexing && countries == 0 { return "Finding your geotagged memories…" }
        return "\(countries) countr\(countries == 1 ? "y" : "ies") · \(continents) continent\(continents == 1 ? "" : "s")"
    }

    private var worldShareSummary: String {
        let visitedCountries = viewModel.countries.filter { $0.photoCount > 0 }
        let places = visitedCountries.prefix(8)
            .map { "\($0.flag) \($0.name)" }
            .joined(separator: ", ")
        let suffix = visitedCountries.count > 8
            ? " and \(visitedCountries.count - 8) more"
            : ""
        return "My Throwbaks world: \(viewModel.visited.count) countries and territories, \(viewModel.visitedContinentCount) continents, and \(viewModel.totalPhotoCount) geotagged memories. \(places)\(suffix)"
    }

    private var shouldShowStatusHint: Bool {
        guard viewModel.selectedCountry == nil else { return false }
        return (viewModel.isIndexing && viewModel.visited.isEmpty)
            || !hasCompletedGlobeOnboarding
    }

    private var statusHint: some View {
        HStack(spacing: 8) {
            if viewModel.isIndexing && viewModel.visited.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text("Finding memories…")
            } else {
                Image(systemName: "hand.draw.fill")
                Text("Spin, zoom, and tap a country")
            }
        }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .environment(\.colorScheme, .dark)
            .padding(.bottom, 8)
    }

    private var limitedLibraryBanner: some View {
        Button {
            photoViewModel.presentLimitedLibraryPicker()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "photo.badge.plus")
                Text("Showing selected memories only")
                Spacer()
                Text("Manage")
                    .fontWeight(.bold)
            }
            .font(.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(.ultraThinMaterial, in: Capsule())
            .environment(\.colorScheme, .dark)
        }
        .padding(.top, 8)
        .accessibilityHint("Choose more memories to include on your world map")
    }

    private var placesNavigationBar: some View {
        HStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                onNavigateToMemories?()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.left")
                    Text("Throwbaks")
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .padding(.horizontal, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
            }
            .accessibilityHint("Returns to your memory timeline")

            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                onNavigateToCreate?()
            } label: {
                HStack(spacing: 7) {
                    Text("Collage")
                    Image(systemName: "chevron.right")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
            }
            .accessibilityHint("Opens collage creation tools")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.22), radius: 5, y: 3)
        .padding(.top, 8)
    }

    private func countryCard(_ country: ExploreCountry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 11) {
                    Text(country.flag)
                        .font(.system(size: 30))
                    Text(country.name)
                        .font(.system(size: 24, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Spacer(minLength: 8)
                    Button {
                        viewModel.dismissCountryKeepingCamera()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.bold())
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.12), in: Circle())
                    }
                    .foregroundStyle(.white.opacity(0.82))
                    .accessibilityLabel("Close country")
                }

                if country.photoCount > 0 {
                    Text(countryMemorySummary(country))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                } else if viewModel.isIndexing {
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.white.opacity(0.76))
                        Text("Still finding geotagged memories…")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                } else {
                    Text("No geotagged memories here yet")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .zIndex(2)
            .fixedSize(horizontal: false, vertical: true)

            if country.photoCount > 0 {
                if viewModel.availableYears.count > 1 {
                    yearFilterMenu
                        .padding(.top, 14)
                }

                CountryPhotoPreviewStrip(
                    photoViewModel: photoViewModel,
                    photos: Array(viewModel.photos.prefix(3))
                )
                .padding(.top, viewModel.availableYears.count > 1 ? 16 : 22)
                .fixedSize(horizontal: false, vertical: true)
                .zIndex(1)
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    showsMemories = true
                }

                Button {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    showsMemories = true
                } label: {
                    HStack {
                        Image(systemName: "photo.stack.fill")
                        Text("View \(viewModel.photos.count.formatted()) memor\(viewModel.photos.count == 1 ? "y" : "ies")")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.10, green: 0.62, blue: 0.35),
                                Color(red: 0.035, green: 0.42, blue: 0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 15)
                    )
                }
                .padding(.top, 16)
            } else if viewModel.isIndexing {
                Text("This place will update as the memory index finishes.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.top, 14)
            } else {
                Text("You can still explore this place on the globe.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.top, 14)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
        .environment(\.colorScheme, .dark)
    }

    private var yearFilterMenu: some View {
        Menu {
            Button {
                viewModel.setYearFilter(nil)
            } label: {
                if viewModel.selectedYear == nil { Label("All years", systemImage: "checkmark") }
                else { Text("All years") }
            }
            ForEach(viewModel.availableYears, id: \.self) { year in
                Button {
                    viewModel.setYearFilter(year)
                } label: {
                    if viewModel.selectedYear == year { Label(String(year), systemImage: "checkmark") }
                    else { Text(String(year)) }
                }
            }
        } label: {
            Label(viewModel.selectedYear.map(String.init) ?? "All years", systemImage: "calendar")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Color.white.opacity(0.11), in: Capsule())
        }
        .accessibilityLabel("Memory year filter")
    }

    private func countryMemorySummary(_ country: ExploreCountry) -> String {
        let visibleCount = viewModel.photos.count
        if let selectedYear = viewModel.selectedYear {
            let memoryLabel = country.photoCount == 1 ? "memory" : "memories"
            return "\(visibleCount.formatted()) of \(country.photoCount.formatted()) \(memoryLabel) · \(selectedYear)"
        }
        let years = viewModel.photos.compactMap { item in
            item.asset.creationDate.map { Calendar.current.component(.year, from: $0) }
        }
        guard let firstYear = years.min(), let lastYear = years.max() else {
            return "\(visibleCount.formatted()) memor\(visibleCount == 1 ? "y" : "ies")"
        }
        let range = firstYear == lastYear ? "\(firstYear)" : "\(firstYear)–\(lastYear)"
        return "\(visibleCount.formatted()) memor\(visibleCount == 1 ? "y" : "ies") · \(range)"
    }

    private func headerCircleIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
            .environment(\.colorScheme, .dark)
            .shadow(color: .black.opacity(0.3), radius: 7, y: 3)
    }
}

private struct CountryPhotoPreviewStrip: View {
    @ObservedObject var photoViewModel: PhotoViewModel
    let photos: [MediaItem]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(photos) { item in
                CountryPreviewThumbnail(photoViewModel: photoViewModel, item: item)
                    .frame(maxWidth: .infinity)
                    .frame(height: 124)
                    // Clip after the final frame so large Photos thumbnails cannot
                    // render over the metadata or primary action rows.
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.34), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.24), radius: 4, y: 2)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 124)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview memories from this place")
        .accessibilityAddTraits(.isButton)
    }
}

private struct WorldDashboardHeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct WorldSummarySheet: View {
    let countryCount: Int
    let continentCount: Int
    let photoCount: Int
    let summaries: [PlaceContinentSummary]
    let visitedCountries: [ExploreCountry]
    let onSelect: (PlaceContinent) -> Void
    let onCountrySelect: (ExploreCountry) -> Void
    @Environment(\.dismiss) private var dismiss
    private let dashboardAccent = Color(red: 0.10, green: 0.62, blue: 0.35)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 11) {
                            Image(systemName: "globe.americas.fill")
                                .font(.title2)
                                .foregroundStyle(dashboardAccent.gradient)
                            Text("Your Memories, Mapped")
                                .font(.system(size: 30, weight: .bold))
                                .tracking(-0.45)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                    }

                    if countryCount == 0 {
                        ContentUnavailableView(
                            "Your visited places will appear as you add geotagged memories.",
                            systemImage: "globe.americas.fill"
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                    } else {
                        HStack(spacing: 10) {
                            metric(
                                value: countryCount,
                                label: countryCount == 1 ? "Country" : "Countries",
                                systemImage: "flag.fill"
                            )
                            metric(
                                value: continentCount,
                                label: continentCount == 1 ? "Continent" : "Continents",
                                systemImage: "map.fill"
                            )
                            metric(
                                value: photoCount,
                                label: photoCount == 1 ? "Memory" : "Memories",
                                systemImage: "photo.stack.fill"
                            )
                        }

                        if !topCountries.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                sectionHeader(
                                    title: "Most Memories"
                                )
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(Array(topCountries.enumerated()), id: \.element.id) { index, country in
                                            topCountryCard(country, rank: index + 1)
                                        }
                                    }
                                    .padding(.horizontal, 1)
                                }
                                .contentMargins(.horizontal, 0, for: .scrollContent)
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader(
                                title: "Continents",
                                detail: "Tap to focus the globe"
                            )
                            VStack(spacing: 0) {
                                ForEach(Array(visitedContinentSummaries.enumerated()), id: \.element.id) { index, summary in
                                    continentRow(summary)
                                    if index < visitedContinentSummaries.count - 1 {
                                        Divider().overlay(Color.white.opacity(0.08))
                                            .padding(.leading, 58)
                                    }
                                }
                            }
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader(
                                title: "Visited places",
                                detail: "\(countryCount.formatted()) countries and territories"
                            )
                            LazyVStack(spacing: 0) {
                                ForEach(Array(alphabeticalCountries.enumerated()), id: \.element.id) { index, country in
                                    Button {
                                        onCountrySelect(country)
                                    } label: {
                                        HStack(spacing: 12) {
                                            Text(country.flag).font(.title3)
                                            Text(country.name)
                                                .font(.body.weight(.medium))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                            Spacer()
                                            Text("\(country.photoCount.formatted()) memor\(country.photoCount == 1 ? "y" : "ies")")
                                                .font(.caption.weight(.medium).monospacedDigit())
                                                .foregroundStyle(.white.opacity(0.58))
                                            Image(systemName: "chevron.right")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white.opacity(0.32))
                                        }
                                        .padding(.horizontal, 15)
                                        .frame(minHeight: 52)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    if index < alphabeticalCountries.count - 1 {
                                        Divider().overlay(Color.white.opacity(0.07))
                                            .padding(.leading, 52)
                                    }
                                }
                            }
                            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.03, green: 0.09, blue: 0.14),
                        Color(red: 0.02, green: 0.04, blue: 0.07)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: shareSummary) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share world summary")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .tint(dashboardAccent)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var topCountries: [ExploreCountry] {
        Array(
            visitedCountries
                .sorted {
                    if $0.photoCount != $1.photoCount { return $0.photoCount > $1.photoCount }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                .prefix(5)
        )
    }

    private var alphabeticalCountries: [ExploreCountry] {
        visitedCountries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var visitedContinentSummaries: [PlaceContinentSummary] {
        summaries.filter { $0.countryCount > 0 }
    }

    private var shareSummary: String {
        let places = visitedCountries.prefix(8).map { "\($0.flag) \($0.name)" }.joined(separator: ", ")
        let suffix = visitedCountries.count > 8 ? " and \(visitedCountries.count - 8) more" : ""
        return "My Throwbaks world: \(countryCount) countries and territories, \(continentCount) continents, and \(photoCount) geotagged memories. \(places)\(suffix)"
    }

    private func metric(value: Int, label: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(dashboardAccent)
            Text(value.formatted())
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.09), Color.white.opacity(0.045)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func sectionHeader(title: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.white)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func topCountryCard(_ country: ExploreCountry, rank: Int) -> some View {
        Button {
            onCountrySelect(country)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(country.flag)
                        .font(.title2)
                    Spacer()
                    Text("#\(rank)")
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(.white.opacity(0.42))
                }
                Text(country.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(country.photoCount.formatted()) memor\(country.photoCount == 1 ? "y" : "ies")")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.62))
            }
            .padding(14)
            .frame(width: 154, height: 112, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [dashboardAccent.opacity(0.2), Color.white.opacity(0.055)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(dashboardAccent.opacity(0.2), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Number \(rank), \(country.name), \(country.photoCount) memories. Focus globe")
    }

    private func continentRow(_ summary: PlaceContinentSummary) -> some View {
        Button {
            onSelect(summary.continent)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: summary.countryCount > 0 ? "location.fill" : "location")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(summary.countryCount > 0 ? dashboardAccent : .white.opacity(0.28))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.continent.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("\(summary.photoCount.formatted()) memor\(summary.photoCount == 1 ? "y" : "ies")")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.54))
                }
                Spacer()
                Text("\(summary.countryCount) countr\(summary.countryCount == 1 ? "y" : "ies")")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(summary.countryCount > 0 ? .white : .white.opacity(0.38))
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.36))
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(summary.continent.name), \(summary.countryCount) countries, \(summary.photoCount) memories. Focus globe"
        )
    }
}

private struct CountryPreviewThumbnail: View {
    @ObservedObject var photoViewModel: PhotoViewModel
    let item: MediaItem
    @State private var thumbnail: UIImage?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(0.08))

            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.75))
            }

            if item.asset.mediaType == .video {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Label(formattedDuration, systemImage: "play.fill")
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.62), in: Capsule())
                            .padding(6)
                    }
                }
            }
        }
        .onAppear(perform: loadThumbnail)
    }

    private var formattedDuration: String {
        let totalSeconds = max(0, Int(item.asset.duration.rounded()))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func loadThumbnail() {
        guard thumbnail == nil, !isLoading else { return }
        if let cached = photoViewModel.cachedThumbnail(for: item.asset) {
            thumbnail = cached
            return
        }

        isLoading = true
        let side = 180 * UIScreen.main.scale
        photoViewModel.requestImage(
            for: item.asset,
            targetSize: CGSize(width: side, height: side)
        ) { image in
            thumbnail = image
            isLoading = false
        }
    }
}

private struct CountryMemoriesView: View {
    @ObservedObject var photoViewModel: PhotoViewModel
    let country: ExploreCountry
    let photos: [MediaItem]
    let countries: [ExploreCountry]
    var subtitle: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDetail: MediaItem?
    @State private var countryCorrectionItem: MediaItem?
    @State private var correctedAssetIDs = Set<String>()

    private let columns = [
        GridItem(.flexible(), spacing: 5),
        GridItem(.flexible(), spacing: 5)
    ]

    private var visiblePhotos: [MediaItem] {
        photos.filter { !correctedAssetIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                    }
                    LazyVGrid(columns: columns, spacing: 5) {
                        ForEach(visiblePhotos) { item in
                            GridItemView(viewModel: photoViewModel, item: item) {
                                selectedDetail = item
                            }
                            .aspectRatio(1, contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .contextMenu {
                                Button {
                                    countryCorrectionItem = item
                                } label: {
                                    Label("Correct country", systemImage: "mappin.and.ellipse")
                                }
                            }
                        }
                    }
                }
                .padding(6)
            }
            .navigationTitle("\(country.flag) \(country.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $selectedDetail) { item in
            MediaDetailView(
                viewModel: photoViewModel,
                itemsForYear: visiblePhotos,
                selectedItemID: item.id,
                yearsAgo: yearsAgo(for: item)
            )
        }
        .sheet(item: $countryCorrectionItem) { item in
            CountryPickerView(
                countries: countries,
                title: "Correct Country"
            ) { correctedCountry in
                Task {
                    await PhotoIndexService.shared.setCountryOverride(
                        correctedCountry.code,
                        forAssetID: item.id
                    )
                    if correctedCountry.code != country.code {
                        correctedAssetIDs.insert(item.id)
                    }
                    countryCorrectionItem = nil
                }
            }
        }
    }

    private func yearsAgo(for item: MediaItem) -> Int {
        guard let date = item.asset.creationDate else { return 0 }
        return max(0, Calendar.current.dateComponents([.year], from: date, to: Date()).year ?? 0)
    }
}

private struct CountryPickerView: View {
    private enum Scope: String, CaseIterable, Identifiable {
        case visited = "Visited"
        case all = "All"
        var id: String { rawValue }
    }

    let countries: [ExploreCountry]
    var title = "Explore Places"
    let onSelect: (ExploreCountry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var scope: Scope = .all

    private var filteredCountries: [ExploreCountry] {
        let scoped = scope == .visited ? countries.filter { $0.photoCount > 0 } : countries
        guard !searchText.isEmpty else { return scoped }
        return scoped.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.code.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Place scope", selection: $scope) {
                    ForEach(Scope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)

                if filteredCountries.isEmpty {
                    ContentUnavailableView(
                        scope == .visited ? "No visited places yet" : "No places found",
                        systemImage: scope == .visited ? "globe" : "magnifyingglass",
                        description: Text(scope == .visited
                            ? "Countries appear here when selected memories include location data."
                            : "Try another country or territory name.")
                    )
                } else {
                    List(filteredCountries) { country in
                        Button { onSelect(country) } label: {
                            HStack {
                                Text(country.flag).font(.title2)
                                Text(country.name).foregroundStyle(.primary)
                                Spacer()
                                if country.photoCount > 0 {
                                    Text(country.photoCount.formatted())
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .searchable(text: $searchText, prompt: "Country or territory")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct GlobeLegendSheet: View {
    @Binding var showsCountryPins: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Map legend") {
                    legendRow(color: .orange, title: "Visited", detail: "A country with geotagged memories")
                    HStack(spacing: 13) {
                        MemoryMapBadge(count: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Country memories")
                            Text("One pin per visited country. Tap to zoom in and view its memories.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Location privacy") {
                    Toggle("Show country pins", isOn: $showsCountryPins)
                    Text("Pins use representative country locations and never reveal an individual memory's exact coordinates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("About the Globe")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func legendRow(color: Color, title: String, detail: String) -> some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.7))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.9), lineWidth: 2))
                .frame(width: 32, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
private enum GoogleMaps3DConfiguration {
    private static var didConfigure = false

    static let apiKey: String? = {
        guard let url = Bundle.main.url(
            forResource: "GoogleMaps3DConfig",
            withExtension: "plist"
        ),
        let data = try? Data(contentsOf: url),
        let values = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any],
        let value = values["GOOGLE_MAPS_3D_API_KEY"] as? String else { return nil }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("PASTE_") else { return nil }
        return trimmed
    }()

    static var isConfigured: Bool { apiKey != nil }

    static func configure() {
        guard !didConfigure, let apiKey else { return }
        didConfigure = true
        GoogleMaps3D.Map.apiKey = apiKey
    }
}

private struct CountryGlobePolygon: Identifiable {
    let id: Int
    let code: String
    let path: [LatLngAltitude]
    let innerPaths: [[LatLngAltitude]]
    let areaProxy: Double

    static let all: [CountryGlobePolygon] = CountryBoundaryDataset.shared.polygons
        .enumerated()
        .compactMap { index, polygon in
            guard let exterior = polygon.rings.first else { return nil }
            let simplifiedExterior = simplified(exterior)
            guard simplifiedExterior.count >= 3 else { return nil }
            return CountryGlobePolygon(
                id: index,
                code: polygon.code,
                path: mapPath(simplifiedExterior),
                innerPaths: polygon.rings.dropFirst()
                    .map(simplified)
                    .filter { $0.count >= 3 }
                    .map(mapPath),
                areaProxy: polygon.areaProxy
            )
        }

    private static let grouped = Dictionary(grouping: all, by: \.code)
        .mapValues { $0.sorted { $0.areaProxy > $1.areaProxy } }

    /// One stable, representative outline per region keeps every independent
    /// country and territory visible even when it is geographically small.
    static let primaryBorders: [CountryGlobePolygon] = grouped
        .values
        .compactMap { polygons in polygons.max(by: { $0.areaProxy < $1.areaProxy }) }
        .sorted { $0.id < $1.id }

    static func visibleBorders(
        visitedCodes: Set<String>,
        selectedCode: String?,
        cameraRange: CLLocationDistance
    ) -> [CountryGlobePolygon] {
        grouped.values.flatMap { polygons in
            let code = polygons.first?.code
            let isSelected = code == selectedCode
            let isVisited = code.map(visitedCodes.contains) ?? false
            let effectiveRange = isSelected || isVisited
                ? cameraRange
                : max(cameraRange, 20_000_000)
            return CountryPolygonLevelOfDetail.selectSorted(
                polygons,
                cameraRange: effectiveRange,
                includeSecondaryComponents: isSelected || isVisited,
                area: \.areaProxy
            )
        }
    }

    private static func simplified(
        _ ring: [CountryBoundaryDataset.Point]
    ) -> [CountryBoundaryDataset.Point] {
        let maximumPoints = 420
        guard ring.count > maximumPoints else { return ring }
        let step = Int(ceil(Double(ring.count) / Double(maximumPoints)))
        var result = ring.enumerated().compactMap { index, point in
            index.isMultiple(of: step) ? point : nil
        }
        if let last = ring.last,
           result.last?.latitude != last.latitude || result.last?.longitude != last.longitude {
            result.append(last)
        }
        return result
    }

    private static func mapPath(
        _ ring: [CountryBoundaryDataset.Point]
    ) -> [LatLngAltitude] {
        ring.map {
            LatLngAltitude(latitude: $0.latitude, longitude: $0.longitude)
        }
    }
}

enum CountryGlobeVisualState: String, Equatable {
    case unvisited
    case visited
    case selected

    static func resolve(
        code: String,
        visitedCodes: Set<String>,
        selectedCode: String?
    ) -> Self {
        if code == selectedCode?.uppercased() { return .selected }
        if visitedCodes.contains(code.uppercased()) { return .visited }
        return .unvisited
    }

    func renderID(for polygonID: Int) -> String {
        "\(polygonID):\(rawValue)"
    }
}

struct CountryGlobeStyleMetrics: Equatable {
    let fillAlpha: Double
    let strokeAlpha: Double
    let strokeWidth: Double

    static func metrics(for visualState: CountryGlobeVisualState) -> Self {
        switch visualState {
        case .selected:
            return Self(fillAlpha: 0.24, strokeAlpha: 0.94, strokeWidth: 3)
        case .visited:
            return Self(fillAlpha: 0.20, strokeAlpha: 0.82, strokeWidth: 2)
        case .unvisited:
            return Self(fillAlpha: 0, strokeAlpha: 0.12, strokeWidth: 0.8)
        }
    }
}

private struct RenderedCountryGlobePolygon: Identifiable {
    let polygon: CountryGlobePolygon
    let visualState: CountryGlobeVisualState

    var id: String { visualState.renderID(for: polygon.id) }
}

private struct CountryMemoryMarker: Identifiable {
    let code: String
    let count: Int
    let coordinate: CLLocationCoordinate2D

    var id: String { code }
}

@MainActor
private struct GooglePlacesGlobeView: View {
    let visited: [CountryPhotoSummary]
    let selectedCode: String?
    let showsCountryPins: Bool
    let target: GlobeTarget?
    let onCountrySelected: (String) -> Void
    let onWorldViewStateChanged: (Bool) -> Void
    @State private var camera: Camera
    @State private var flightDestination: Camera
    @State private var flightState = GlobeFlightRequestState()

    init(
        visited: [CountryPhotoSummary],
        selectedCode: String?,
        showsCountryPins: Bool,
        target: GlobeTarget?,
        onCountrySelected: @escaping (String) -> Void,
        onWorldViewStateChanged: @escaping (Bool) -> Void
    ) {
        self.visited = visited
        self.selectedCode = selectedCode
        self.showsCountryPins = showsCountryPins
        self.target = target
        self.onCountrySelected = onCountrySelected
        self.onWorldViewStateChanged = onWorldViewStateChanged
        _camera = State(initialValue: Self.introCamera)
        _flightDestination = State(initialValue: Self.introCamera)
        GoogleMaps3DConfiguration.configure()
    }

    private var visitedCodes: Set<String> {
        Set(visited.map { $0.code.uppercased() })
    }

    private var normalizedSelectedCode: String? {
        selectedCode?.uppercased()
    }

    private var isAwayFromWorld: Bool {
        camera.range < 30_000_000
    }

    private var visiblePolygons: [RenderedCountryGlobePolygon] {
        let visitedCodes = visitedCodes
        let selectedCode = normalizedSelectedCode
        return CountryGlobePolygon.visibleBorders(
            visitedCodes: visitedCodes,
            selectedCode: selectedCode,
            cameraRange: camera.range
        )
        .map { polygon in
            RenderedCountryGlobePolygon(
                polygon: polygon,
                visualState: .resolve(
                    code: polygon.code,
                    visitedCodes: visitedCodes,
                    selectedCode: selectedCode
                )
            )
        }
    }

    private var countryMemoryMarkers: [CountryMemoryMarker] {
        guard showsCountryPins, normalizedSelectedCode == nil else { return [] }
        let cameraCenter = CLLocationCoordinate2D(
            latitude: camera.center.latitude,
            longitude: camera.center.longitude
        )
        return visited.compactMap { summary in
            guard let coordinate = CountryBoundaryDataset.shared.representativeCoordinate(
                for: summary.code
            ) else { return nil }
            return CountryMemoryMarker(
                code: summary.code,
                count: summary.photoCount,
                coordinate: coordinate
            )
        }
        .filter {
            CountryOverviewMarkerVisibilityPolicy.isVisible(
                coordinate: $0.coordinate,
                cameraCenter: cameraCenter,
                cameraRange: camera.range
            )
        }
    }

    var body: some View {
        if GoogleMaps3DConfiguration.isConfigured {
            map
        } else {
            missingKeyView
        }
    }

    private var map: some View {
        GoogleMaps3D.Map(camera: $camera, mode: .satellite) {
            // Satellite mode removes competing basemap text. Representative
            // global borders plus full visited borders preserve discoverability.
            ForEach(visiblePolygons) { rendered in
                let polygon = rendered.polygon
                GoogleMaps3D.Polygon(
                    path: polygon.path,
                    innerPaths: polygon.innerPaths,
                    altitudeMode: .clampToGround,
                    zIndex: zIndex(for: rendered.visualState)
                )
                .style(style(for: rendered.visualState))
                .onTap {
                    selectCountry(from: polygon)
                }
            }

            // One stable aggregate per visited country keeps the globe quiet
            // and predictable. Selecting it hides the pin and opens the card.
            ForEach(countryMemoryMarkers) { marker in
                Marker3D(
                    position: LatLngAltitude(
                        latitude: marker.coordinate.latitude,
                        longitude: marker.coordinate.longitude
                    ),
                    altitudeMode: .clampToGround,
                    collisionBehavior: .optionalAndHidesLowerPriority,
                    extruded: false,
                    drawsWhenOccluded: false,
                    sizePreserved: true,
                    zIndex: 120,
                    label: "",
                    style: .viewSnapshot {
                        MemoryMapBadge(
                            count: marker.count,
                            scale: camera.range >= 18_000_000 ? .world : .overview
                        )
                    }
                )
                .onTap {
                    onCountrySelected(marker.code)
                }
            }

            if let selectedCode = normalizedSelectedCode,
               CountryBoundaryDataset.shared.polygons(for: selectedCode).isEmpty,
               let target,
               target.countryCode == selectedCode,
               let selectionCoordinate = CountryBoundaryDataset.shared.representativeCoordinate(
                   for: selectedCode
               ) {
                Marker3D(
                    position: LatLngAltitude(
                        latitude: selectionCoordinate.latitude,
                        longitude: selectionCoordinate.longitude
                    ),
                    altitudeMode: .clampToGround,
                    collisionBehavior: .required,
                    extruded: false,
                    drawsWhenOccluded: false,
                    sizePreserved: true,
                    zIndex: 110,
                    label: selectedCode,
                    style: .viewSnapshot {
                        MissingBoundaryBadge()
                    }
                )
            }
        }
        .flyCameraTo(
            flightDestination,
            duration: 1.5,
            trigger: flightState.firedID,
            completion: { settleActiveFlight(reason: "completion") }
        )
        .onAppear {
            scheduleFlight(to: target)
        }
        .onChange(of: target?.id) { _, _ in
            scheduleFlight(to: target)
        }
        .onChange(of: isAwayFromWorld, initial: true) { _, isAway in
            onWorldViewStateChanged(isAway)
        }
        .task(id: flightState.stagedID) {
            await fireStagedFlight()
        }
    }

    private func style(for visualState: CountryGlobeVisualState) -> GoogleMaps3D.Polygon.StyleOptions {
        let metrics = CountryGlobeStyleMetrics.metrics(for: visualState)
        let amber = UIColor(red: 1, green: 0.52, blue: 0.12, alpha: 1)
        let fillColor: UIColor
        let strokeColor: UIColor

        switch visualState {
        case .selected:
            fillColor = amber.withAlphaComponent(metrics.fillAlpha)
            strokeColor = UIColor.white.withAlphaComponent(metrics.strokeAlpha)
        case .visited:
            fillColor = amber.withAlphaComponent(metrics.fillAlpha)
            strokeColor = amber.withAlphaComponent(metrics.strokeAlpha)
        case .unvisited:
            fillColor = .clear
            strokeColor = UIColor.white.withAlphaComponent(metrics.strokeAlpha)
        }

        return GoogleMaps3D.Polygon.StyleOptions(
            fillColor: fillColor,
            strokeColor: strokeColor,
            strokeWidth: metrics.strokeWidth,
            geodesic: true,
            extruded: false,
            drawsOccludedSegments: false
        )
    }

    private func zIndex(for visualState: CountryGlobeVisualState) -> Int32 {
        switch visualState {
        case .selected: return 100
        case .visited: return 40
        case .unvisited: return 0
        }
    }

    private func selectCountry(from polygon: CountryGlobePolygon) {
#if DEBUG
        print("🌍 Places polygon tap iso=\(polygon.code)")
#endif
        onCountrySelected(polygon.code)
    }

    private func scheduleFlight(to target: GlobeTarget?) {
        guard let target else {
            flightState.cancel()
            return
        }
        guard flightState.accept(target) else { return }
        // Stage the destination without changing the animation trigger. The
        // task below fires on a subsequent render, preventing the SDK from
        // pairing a new trigger with the previous render's camera value.
        flightDestination = Self.camera(for: target)
#if DEBUG
        print(
            "🌍 Places staged flight trigger=\(target.id.uuidString) "
                + "iso=\(target.countryCode ?? "none") source=\(target.source.rawValue) target="
                + "\(String(format: "%.2f", target.coordinate.latitude)),"
                + "\(String(format: "%.2f", target.coordinate.longitude)) range=\(Int(target.distance))"
        )
#endif
    }

    private func fireStagedFlight() async {
        guard let stagedID = flightState.stagedID else { return }
        // Yielding from a task keyed to stagedID guarantees at least one view
        // update has carried flightDestination to the map modifier first.
        await Task.yield()
        guard !Task.isCancelled,
              let fired = flightState.markDestinationRendered(stagedID) else { return }
#if DEBUG
        print(
            "🌍 Places fired flight trigger=\(fired.id.uuidString) "
                + "iso=\(fired.countryCode ?? "none")"
        )
#endif
        do {
            try await Task.sleep(nanoseconds: 1_800_000_000)
        } catch {
            return
        }
        guard !Task.isCancelled, flightState.active?.id == fired.id else { return }
        settleActiveFlight(reason: "watchdog")
    }

    private func settleActiveFlight(reason: String) {
        guard let active = flightState.active else { return }
        guard flightState.allowsCorrection else {
#if DEBUG
            print(
                "🌍 Places skipped duplicate \(reason) correction "
                    + "trigger=\(active.id.uuidString)"
            )
#endif
            return
        }
        let snapshot = GlobeCameraSnapshot(
            latitude: camera.center.latitude,
            longitude: camera.center.longitude,
            range: camera.range
        )
        let needsCorrection = GlobeCameraAlignment.needsCorrection(snapshot, for: active)
#if DEBUG
        print(
            "🌍 Places \(reason) trigger=\(active.id.uuidString) iso="
                + "\(active.countryCode ?? "none") corrected=\(needsCorrection) live="
                + "\(String(format: "%.2f", camera.center.latitude)),"
                + "\(String(format: "%.2f", camera.center.longitude)) range=\(Int(camera.range))"
        )
        if active.countryCode != normalizedSelectedCode {
            assertionFailure("Places camera request ISO did not match the selected card")
        }
#endif
        if needsCorrection {
            // Completion callbacks from superseded SDK animations all converge
            // on the newest semantic request, so an older flight cannot win.
            camera = Self.camera(for: active)
        }
        flightState.finishCorrection()
    }

    private static let introCamera = Camera(
        center: LatLngAltitude(latitude: 14, longitude: 0),
        heading: -10,
        tilt: 0,
        roll: 0,
        range: 35_000_000,
        fieldOfView: .degrees(40),
        altitudeMode: .relativeToGround
    )

    private static func camera(for target: GlobeTarget) -> Camera {
        let tilt: Double
        if target.countryCode != nil, target.distance <= 350_000 {
            tilt = 22
        } else if target.countryCode != nil, target.distance <= 2_500_000 {
            tilt = 14
        } else if target.countryCode != nil {
            tilt = 6
        } else {
            tilt = 0
        }
        return Camera(
            center: LatLngAltitude(
                latitude: target.coordinate.latitude,
                longitude: target.coordinate.longitude
            ),
            heading: 0,
            tilt: tilt,
            roll: 0,
            range: min(63_000_000, max(25_000, target.distance)),
            fieldOfView: .degrees(42),
            altitudeMode: .relativeToGround
        )
    }

    private var missingKeyView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.10, blue: 0.18),
                    Color(red: 0.01, green: 0.03, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 14) {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 76, weight: .light))
                    .foregroundStyle(.blue.gradient)
                    .shadow(color: .cyan.opacity(0.35), radius: 24)
                Text("Google 3D globe is ready")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("Add your Maps 3D API key to GoogleMaps3DConfig.plist to load the live globe.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(maxWidth: 300)
            }
            .padding(.top, 90)
        }
    }
}

private enum MemoryMapBadgeScale: Equatable {
    case world
    case overview
}

private struct MemoryMapBadge: View {
    let count: Int
    var scale: MemoryMapBadgeScale = .overview

    var body: some View {
        ZStack(alignment: .top) {
            MemoryPinShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.62, blue: 0.35),
                            Color(red: 0.035, green: 0.42, blue: 0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    MemoryPinShape()
                        .stroke(.white.opacity(0.76), lineWidth: 0.9)
                )
                .frame(width: pinWidth, height: pinHeight)

            Text(compactCount)
                .font(.system(size: labelSize, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(1)
                .allowsTightening(true)
                .minimumScaleFactor(0.55)
                .frame(width: pinWidth - 2, height: pinWidth - 1)
        }
        .frame(width: markerFrame.width, height: markerFrame.height)
        .shadow(color: .black.opacity(0.34), radius: 3, y: 2)
        .accessibilityLabel("\(count) memor\(count == 1 ? "y" : "ies") in this country")
    }

    private var pinWidth: CGFloat {
        switch scale {
        case .world:
            if count >= 1_000 { return 24 }
            if count >= 100 { return 22 }
            if count >= 10 { return 18 }
            return 16
        case .overview:
            if count >= 1_000 { return 27 }
            if count >= 100 { return 24 }
            if count >= 10 { return 20 }
            return 18
        }
    }

    private var pinHeight: CGFloat {
        switch scale {
        case .world: return pinWidth + 5
        case .overview: return pinWidth + 6
        }
    }

    private var labelSize: CGFloat {
        switch scale {
        case .world: return count >= 1_000 ? 6 : 6.5
        case .overview: return count >= 1_000 ? 6.5 : 7
        }
    }

    private var markerFrame: CGSize {
        switch scale {
        case .world: return CGSize(width: 29, height: 32)
        case .overview: return CGSize(width: 32, height: 35)
        }
    }

    private var compactCount: String {
        guard count >= 1_000 else { return count.formatted() }
        let thousands = Double(count) / 1_000
        return thousands >= 10
            ? String(format: "%.0fK", thousands)
            : String(format: "%.1fK", thousands)
    }
}

private struct MemoryPinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let midpoint = CGPoint(x: rect.midX, y: rect.width / 2)
        let tip = CGPoint(x: rect.midX, y: rect.maxY)
        let left = CGPoint(x: rect.minX, y: midpoint.y)
        let top = CGPoint(x: rect.midX, y: rect.minY)
        let right = CGPoint(x: rect.maxX, y: midpoint.y)
        let shoulderControl = rect.width * 0.23

        var path = Path()
        path.move(to: tip)
        path.addCurve(
            to: left,
            control1: CGPoint(x: rect.midX - 4, y: rect.maxY - 9),
            control2: CGPoint(x: rect.minX, y: midpoint.y + shoulderControl)
        )
        path.addCurve(
            to: top,
            control1: CGPoint(x: rect.minX, y: midpoint.y - shoulderControl),
            control2: CGPoint(x: rect.midX - shoulderControl, y: rect.minY)
        )
        path.addCurve(
            to: right,
            control1: CGPoint(x: rect.midX + shoulderControl, y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: midpoint.y - shoulderControl)
        )
        path.addCurve(
            to: tip,
            control1: CGPoint(x: rect.maxX, y: midpoint.y + shoulderControl),
            control2: CGPoint(x: rect.midX + 4, y: rect.maxY - 9)
        )
        path.closeSubpath()
        return path
    }
}

private struct MissingBoundaryBadge: View {
    var body: some View {
        ZStack(alignment: .top) {
            MemoryPinShape()
                .fill(Color(red: 0.06, green: 0.52, blue: 0.28))
                .overlay(MemoryPinShape().stroke(.white.opacity(0.76), lineWidth: 0.9))
                .frame(width: 21, height: 28)
            Circle()
                .fill(.white)
                .frame(width: 5, height: 5)
                .padding(.top, 7)
        }
            .frame(width: 31, height: 34)
            .shadow(color: .black.opacity(0.34), radius: 3, y: 2)
            .accessibilityLabel("Selected country")
    }
}
