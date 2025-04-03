import SwiftUI
import Photos
import MapKit

struct LocationInfoPanelView: View {
    let asset: PHAsset

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var placemarkString: String? = nil
    @State private var mapAnnotationCoordinate: CLLocationCoordinate2D? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let coordinate = mapAnnotationCoordinate {
                Map(position: $cameraPosition) {
                    Marker("", coordinate: coordinate)
                        .tint(Color.accentColor)
                }
                .mapStyle(.standard(elevation: .realistic))
                .frame(height: 180)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            } else if asset.location != nil {
                ProgressView().frame(height: 180)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let address = placemarkString {
                    Text(address)
                        .font(.headline)
                        .lineLimit(2)
                } else if mapAnnotationCoordinate != nil {
                    Text("Loading address...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("No Location Information")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }

                if let date = asset.creationDate {
                    Text(date.formatted(date: .long, time: .shortened))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, mapAnnotationCoordinate != nil ? 8 : 0)

            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.top, 15)
        .padding(.bottom, 30)
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
