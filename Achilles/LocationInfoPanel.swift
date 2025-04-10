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
        // Just the map with minimal overlay
        GeometryReader { geometry in
            ZStack {
                if let coordinate = mapAnnotationCoordinate {
                    // The map without any container
                    Map(position: $cameraPosition) {
                        Marker("", coordinate: coordinate)
                            .tint(Color.accentColor)
                    }
                    .mapStyle(.standard(elevation: .flat))
                    .clipShape(RoundedRectangle(cornerRadius: 24)) // Larger corner radius
                    .shadow(color: .black.opacity(0.25), radius: 15, x: 0, y: 3)
                    
                    // X button to dismiss the map
                    .overlay(
                        Button {
                            NotificationCenter.default.post(
                                name: Notification.Name("DismissMapPanel"),
                                object: nil
                            )
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.8))
                                    .frame(width: 40, height: 40)
                                    .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 2)
                                
                                Image(systemName: "xmark")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(12)
                        .zIndex(10),
                        alignment: .topTrailing
                    )
                    
                    // Location text overlay with gradient - tightly fit to text
                    .overlay(
                        VStack {
                            if let address = placemarkString {
                                HStack {
                                    Spacer()
                                    Text(address)
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.7), radius: 1, x: 0, y: 1)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule()
                                                .fill(Color.black.opacity(0.5))
                                        )
                                    Spacer()
                                }
                                .frame(maxWidth: geometry.size.width - 90)
                                .padding(.top, 20)
                            }
                            
                            Spacer()
                        }
                    )
                    
                    // Better expand button overlay
                    .overlay(
                        Button {
                            showFullScreenMap = true
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right.circle.fill")
                                .font(.system(size: 32, weight: .regular))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 1)
                                .padding(8)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.2))
                                        .blur(radius: 4)
                                )
                        }
                        .padding(20),
                        alignment: .bottomTrailing
                    )
                    .sheet(isPresented: $showFullScreenMap) {
                        FullScreenMapView(
                            coordinate: coordinate,
                            locationName: placemarkString ?? "Photo Location",
                            cameraPosition: cameraPosition,
                            date: asset.creationDate
                        )
                    }
                } else if asset.location != nil {
                    // Loading state
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.black.opacity(0.1))
                            .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: 3)
                        
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                    }
                    .frame(height: 300)
                } else {
                    // No location info
                    Color.clear
                        .frame(height: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
    let date: Date?
    
    @Environment(\.dismiss) private var dismiss
    @State private var showHybrid = false
    @State private var customMapPosition: MapCameraPosition
    
    init(coordinate: CLLocationCoordinate2D, locationName: String, cameraPosition: MapCameraPosition, date: Date? = nil) {
        self.coordinate = coordinate
        self.locationName = locationName
        self.cameraPosition = cameraPosition
        self.date = date
        
        // Initialize with a closer zoom level
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        )
        self._customMapPosition = State(initialValue: .region(region))
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Full screen map
                Map(position: $customMapPosition) {
                    Marker(locationName, coordinate: coordinate)
                        .tint(Color.accentColor)
                }
                .mapStyle(showHybrid ? .hybrid(elevation: .realistic) : .standard(elevation: .flat))
                .ignoresSafeArea(edges: [.horizontal, .bottom])
                
                // Header - more translucent and elegant
                VStack(spacing: 4) {
                    Text(locationName)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if let date = date {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
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


