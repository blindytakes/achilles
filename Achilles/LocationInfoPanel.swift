import SwiftUI
import Photos
import MapKit

struct LocationInfoPanelView: View {
    let asset: PHAsset

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var placemarkString: String? = nil
    @State private var mapAnnotationCoordinate: CLLocationCoordinate2D? = nil
    @State private var showFullScreenMap = false

    var body: some View {
        VStack(spacing: 16) {
            // Location text at the top
            if let address = placemarkString {
                Text(address)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if mapAnnotationCoordinate != nil {
                Text("Loading address...")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if asset.location == nil {
                Text("No Location Information")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            // Map centered in the panel
            if let coordinate = mapAnnotationCoordinate {
                Map(position: $cameraPosition) {
                    Marker("", coordinate: coordinate)
                        .tint(Color.accentColor)
                }
                .mapStyle(.standard(elevation: .flat))
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .overlay(
                    ZStack {
                        // Full-size tap target
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                showFullScreenMap = true
                            }
                        
                        // Visual indicator - more subtle
                        Image(systemName: "arrow.up.right.and.arrow.down.left")
                            .font(.system(size: 18))
                            .padding(6)
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(6)
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                )
                .sheet(isPresented: $showFullScreenMap) {
                    FullScreenMapView(
                        coordinate: coordinate,
                        locationName: placemarkString ?? "Photo Location",
                        cameraPosition: cameraPosition
                    )
                }
            } else if asset.location != nil {
                ProgressView()
                    .frame(height: 200)
            } else {
                VStack {
                    Image(systemName: "location.slash.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                    
                    Text("No Location Information")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .cornerRadius(10)
            }

            // Date information at the bottom
            if let date = asset.creationDate {
                Text(date.formatted(date: .long, time: .shortened))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Spacer(minLength: 5)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .onAppear(perform: setupLocationData)
        .onChange(of: asset.localIdentifier) { _, _ in
            setupLocationData()
        }
    }

    @MainActor private func setupLocationData() {
        self.cameraPosition = .automatic
        self.placemarkString = nil
        self.mapAnnotationCoordinate = nil

        guard let location = asset.location else { return }

        let coordinate = location.coordinate
        self.mapAnnotationCoordinate = coordinate

        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 750,
            longitudinalMeters: 750
        )
        self.cameraPosition = .region(region)

        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            guard self.asset.localIdentifier == asset.localIdentifier else { return }

            if let error = error {
                print("Reverse geocoding error: \(error.localizedDescription)")
                self.placemarkString = "Address not found"
                return
            }

            guard let placemark = placemarks?.first else {
                self.placemarkString = "Unknown Location Details"
                return
            }

            var addressComponents: [String] = []
            if let name = placemark.name, !name.contains("Unnamed Road") {
                addressComponents.append(name)
            }
            if let city = placemark.locality {
                addressComponents.append(city)
            }
            if let area = placemark.administrativeArea {
                addressComponents.append(area)
            }

            let constructedAddress = addressComponents.joined(separator: ", ")
            self.placemarkString = constructedAddress.isEmpty ? "Nearby Location" : constructedAddress
        }
    }
}

// Full screen map view
struct FullScreenMapView: View {
    let coordinate: CLLocationCoordinate2D
    let locationName: String
    let cameraPosition: MapCameraPosition
    
    @Environment(\.dismiss) private var dismiss
    @State private var mapStyle: MapStyle = .standard(elevation: .realistic)
    @State private var showHybrid = false
    @State private var customMapPosition: MapCameraPosition
    
    init(coordinate: CLLocationCoordinate2D, locationName: String, cameraPosition: MapCameraPosition) {
        self.coordinate = coordinate
        self.locationName = locationName
        self.cameraPosition = cameraPosition
        
        // Initialize with a closer zoom level
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        )
        self._customMapPosition = State(initialValue: .region(region))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Title and location display
                Text(locationName)
                    .font(.headline)
                    .lineLimit(1)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemBackground))
                
                // Full screen map
                Map(position: $customMapPosition) {
                    Marker(locationName, coordinate: coordinate)
                        .tint(Color.accentColor)
                }
                .mapStyle(showHybrid ? .hybrid(elevation: .realistic) : .standard(elevation: .flat))
                .ignoresSafeArea(edges: [.horizontal])
                .edgesIgnoringSafeArea(.bottom)
                
                // Date info at bottom
                Text(Date().formatted(date: .long, time: .shortened))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemBackground))
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(showHybrid ? "Map" : "Satellite") {
                        showHybrid.toggle()
                    }
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
            MKLaunchOptionsMapSpanKey: NSValue(mkCoordinateSpan: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        ])
    }
}

