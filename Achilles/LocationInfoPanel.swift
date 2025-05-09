//
// LocationInfoPanelView.swift
//
// Presents an interactive map panel for a photo’s location.
//
// Key features:
// - Displays an embedded MapKit view with a pin at the photo’s GPS coordinate
// - Debounces reverse‑geocode address lookups via the view model’s placemark cache
// - “X” button to dismiss the panel back to the parent view
// - “Expand” button to show a full‑screen map with controls and share options
// - Shows a loading state while waiting for 



import SwiftUI
import Photos
import MapKit

struct LocationInfoPanelView: View {
    let asset: PHAsset
    @ObservedObject var viewModel: PhotoViewModel
    let onDismiss: () -> Void

    @State private var placemarkString: String?
    @State private var debounceWork: DispatchWorkItem?

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var mapAnnotationCoordinate: CLLocationCoordinate2D?
    @State private var showFullScreenMap = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let coord = mapAnnotationCoordinate {
                    // Embedded map
                    Map(position: $cameraPosition) {
                        Marker("", coordinate: coord)
                    }
                    .mapStyle(.standard(elevation: .flat))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.25), radius: 15, x: 0, y: 3)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Map showing photo location")

                    // Dismiss button
                    .overlay(dismissButton, alignment: .topTrailing)

                    // Address overlay
                    .overlay(addressOverlay(geo: geo), alignment: .top)

                    // Expand button
                    .overlay(expandButton, alignment: .bottomTrailing)

                    // Full‑screen sheet
                    .sheet(isPresented: $showFullScreenMap) {
                        FullScreenMapView(
                            coordinate: coord,
                            locationName: placemarkString ?? "Photo Location",
                            cameraPosition: cameraPosition,
                            date: asset.creationDate
                        )
                    }

                } else if asset.location != nil {
                    // Loading state
                    loadingView
                } else {
                    // No location metadata
                    Color.clear.frame(height: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            // Position map
            if let loc = asset.location {
                let coord = loc.coordinate
                mapAnnotationCoordinate = coord
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: coord,
                        latitudinalMeters: 750,
                        longitudinalMeters: 750
                    )
                )
            }
            // Kick off address lookup
            schedulePlacemark()
        }
        .onChange(of: asset.localIdentifier) {
            mapAnnotationCoordinate = nil
            cameraPosition = .automatic
            placemarkString = nil
            schedulePlacemark()
        }
    }

    // MARK: - Subviews

    private var dismissButton: some View {
        Button {
            onDismiss()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.8))
                    .frame(width: 40, height: 40)
                    .shadow(radius: 2)
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundColor(.white)
            }
        }
        .padding(12)
        .accessibilityLabel("Dismiss map panel")
    }

    private func addressOverlay(geo: GeometryProxy) -> some View {
        VStack {
            if let address = placemarkString {
                HStack {
                    Spacer()
                    Text(address)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .shadow(radius: 1)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.5)))
                    Spacer()
                }
                .frame(maxWidth: geo.size.width - 90)
                .padding(.top, 20)
            }
            Spacer()
        }
    }

    private var expandButton: some View {
        Button {
            showFullScreenMap = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right.circle.fill")
                .font(.title)
                .foregroundColor(.white)
                .shadow(radius: 1)
        }
        .padding(20)
        .accessibilityLabel("Expand to full-screen map")
    }

    private var loadingView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.black.opacity(0.1))
                .shadow(radius: 3)
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.2)
        }
        .frame(height: 300)
    }

    // MARK: - Helpers

    private func schedulePlacemark() {
        debounceWork?.cancel()
        let work = DispatchWorkItem {
            Task {
                placemarkString = await viewModel.placemark(for: asset)
            }
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func openInMaps(coordinate: CLLocationCoordinate2D, name: String) {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinate),
            MKLaunchOptionsMapSpanKey: NSValue(
                mkCoordinateSpan: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        ])
    }
}


/// Full‑screen map view with controls
struct FullScreenMapView: View {
    let coordinate: CLLocationCoordinate2D
    let locationName: String
    let cameraPosition: MapCameraPosition
    let date: Date?

    @Environment(\.dismiss) private var dismiss
    @State private var showHybrid = false
    @State private var customMapPosition: MapCameraPosition

    init(
        coordinate: CLLocationCoordinate2D,
        locationName: String,
        cameraPosition: MapCameraPosition,
        date: Date? = nil
    ) {
        self.coordinate = coordinate
        self.locationName = locationName
        self.cameraPosition = cameraPosition
        self.date = date

        // Start zoomed in a bit closer
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        )
        self._customMapPosition = State(initialValue: .region(region))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Map(position: $customMapPosition) {
                    Marker(locationName, coordinate: coordinate)
                }
                .mapStyle(showHybrid ? .hybrid(elevation: .realistic) : .standard(elevation: .flat))
                .ignoresSafeArea(edges: [.horizontal, .bottom])

                VStack(spacing: 4) {
                    Text(locationName)
                        .font(.headline)
                        .lineLimit(1)
                    if let date = date {
                        Text(date.abbreviatedDateShortTime())
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .background(Material.thin)
                .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(showHybrid ? "Map" : "Satellite") { showHybrid.toggle() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        openInMaps(coordinate: coordinate, name: locationName)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private func openInMaps(coordinate: CLLocationCoordinate2D, name: String) {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinate),
            MKLaunchOptionsMapSpanKey: NSValue(
                mkCoordinateSpan: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        ])
    }
}
