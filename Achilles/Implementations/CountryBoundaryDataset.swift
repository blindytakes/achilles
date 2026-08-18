import Foundation
import CoreLocation

/// Immutable, on-device country geometry used by both the photo index and the
/// 3D globe. Country assignment never depends on network geocoding.
final class CountryBoundaryDataset: @unchecked Sendable {
    struct Point: Sendable {
        let longitude: Double
        let latitude: Double
    }

    struct Polygon: Sendable {
        let code: String
        let rings: [[Point]]
        let minLatitude: Double
        let maxLatitude: Double
        let minLongitude: Double
        let maxLongitude: Double
        /// Approximate surface area in square degrees, corrected for latitude.
        /// Unlike a longitude bounding box, this remains stable for polygons
        /// which cross the antimeridian.
        let areaProxy: Double

        func contains(latitude: Double, longitude: Double) -> Bool {
            guard latitude >= minLatitude, latitude <= maxLatitude else { return false }
            // A polygon spanning the antimeridian has a misleading ordinary
            // longitude bounding box, so let the unwrapped ring test decide.
            if maxLongitude - minLongitude < 180,
               !(longitude >= minLongitude && longitude <= maxLongitude) {
                return false
            }
            guard let exterior = rings.first,
                  Self.ringContains(exterior, latitude: latitude, longitude: longitude) else {
                return false
            }
            return !rings.dropFirst().contains {
                Self.ringContains($0, latitude: latitude, longitude: longitude)
            }
        }

        /// Natural Earth intentionally omits some tiny coastal islands at this
        /// detail level. GPS coordinates can also land a few metres offshore.
        /// Use the exterior edge as a conservative fallback after exact tests.
        func distanceToExteriorKilometres(latitude: Double, longitude: Double) -> Double {
            guard let exterior = rings.first, exterior.count >= 2 else {
                return .greatestFiniteMagnitude
            }
            let longitudes = Self.unwrappedLongitudes(for: exterior)
            var testLongitude = longitude
            while testLongitude - longitudes[0] > 180 { testLongitude -= 360 }
            while testLongitude - longitudes[0] < -180 { testLongitude += 360 }

            let longitudeScale = max(cos(latitude * .pi / 180), 0.15)
            let testX = testLongitude * longitudeScale
            let testY = latitude
            var bestSquared = Double.greatestFiniteMagnitude

            for current in exterior.indices {
                let previous = current == 0 ? exterior.count - 1 : current - 1
                let startX = longitudes[previous] * longitudeScale
                let startY = exterior[previous].latitude
                let endX = longitudes[current] * longitudeScale
                let endY = exterior[current].latitude
                let deltaX = endX - startX
                let deltaY = endY - startY
                let lengthSquared = deltaX * deltaX + deltaY * deltaY
                let projection: Double
                if lengthSquared == 0 {
                    projection = 0
                } else {
                    projection = min(
                        1,
                        max(0, ((testX - startX) * deltaX + (testY - startY) * deltaY) / lengthSquared)
                    )
                }
                let closestX = startX + projection * deltaX
                let closestY = startY + projection * deltaY
                let distanceX = testX - closestX
                let distanceY = testY - closestY
                bestSquared = min(bestSquared, distanceX * distanceX + distanceY * distanceY)
            }
            return sqrt(bestSquared) * 111.2
        }

        private static func ringContains(
            _ ring: [Point],
            latitude: Double,
            longitude: Double
        ) -> Bool {
            guard ring.count >= 3 else { return false }
            let longitudes = unwrappedLongitudes(for: ring)
            var testLongitude = longitude
            while testLongitude - longitudes[0] > 180 { testLongitude -= 360 }
            while testLongitude - longitudes[0] < -180 { testLongitude += 360 }

            var inside = false
            var previous = ring.count - 1
            for current in ring.indices {
                let currentLatitude = ring[current].latitude
                let previousLatitude = ring[previous].latitude
                let crosses = (currentLatitude > latitude) != (previousLatitude > latitude)
                if crosses {
                    let intersection = (longitudes[previous] - longitudes[current])
                        * (latitude - currentLatitude)
                        / (previousLatitude - currentLatitude)
                        + longitudes[current]
                    if testLongitude < intersection { inside.toggle() }
                }
                previous = current
            }
            return inside
        }

        fileprivate static func unwrappedLongitudes(for ring: [Point]) -> [Double] {
            guard let first = ring.first else { return [] }
            var result = [first.longitude]
            result.reserveCapacity(ring.count)
            for point in ring.dropFirst() {
                var longitude = point.longitude
                let previous = result[result.count - 1]
                while longitude - previous > 180 { longitude -= 360 }
                while longitude - previous < -180 { longitude += 360 }
                result.append(longitude)
            }
            return result
        }

        fileprivate static func areaProxy(for ring: [Point]) -> Double {
            guard ring.count >= 3 else { return 0 }
            let longitudes = unwrappedLongitudes(for: ring)
            let meanLatitude = ring.map(\.latitude).reduce(0, +) / Double(ring.count)
            var signedArea = 0.0
            for current in ring.indices {
                let previous = current == 0 ? ring.count - 1 : current - 1
                signedArea += longitudes[previous] * ring[current].latitude
                    - longitudes[current] * ring[previous].latitude
            }
            return abs(signedArea) * 0.5 * max(cos(meanLatitude * .pi / 180), 0.15)
        }

        fileprivate func centroid() -> CLLocationCoordinate2D? {
            guard let exterior = rings.first, exterior.count >= 3 else { return nil }
            let longitudes = Self.unwrappedLongitudes(for: exterior)
            var signedAreaTimesTwo = 0.0
            var longitudeTotal = 0.0
            var latitudeTotal = 0.0

            for current in exterior.indices {
                let previous = current == 0 ? exterior.count - 1 : current - 1
                let cross = longitudes[previous] * exterior[current].latitude
                    - longitudes[current] * exterior[previous].latitude
                signedAreaTimesTwo += cross
                longitudeTotal += (longitudes[previous] + longitudes[current]) * cross
                latitudeTotal += (exterior[previous].latitude + exterior[current].latitude) * cross
            }

            guard abs(signedAreaTimesTwo) > 0.000_000_1 else { return nil }
            var longitude = longitudeTotal / (3 * signedAreaTimesTwo)
            while longitude > 180 { longitude -= 360 }
            while longitude < -180 { longitude += 360 }
            return CLLocationCoordinate2D(
                latitude: latitudeTotal / (3 * signedAreaTimesTwo),
                longitude: longitude
            )
        }
    }

    static let shared = CountryBoundaryDataset(
        resourceURL: Bundle.main.url(forResource: "country_boundaries", withExtension: "geojson")
    )

    private static let fallbackTargets: [String: (CLLocationCoordinate2D, CLLocationDistance)] = [
        "AC": (.init(latitude: -7.95, longitude: -14.36), 250_000),
        "BV": (.init(latitude: -54.42, longitude: 3.36), 250_000),
        "CP": (.init(latitude: 10.30, longitude: -109.22), 150_000),
        "CQ": (.init(latitude: 49.43, longitude: -2.36), 50_000),
        "DG": (.init(latitude: -7.32, longitude: 72.42), 250_000),
        "EA": (.init(latitude: 35.90, longitude: -5.30), 220_000),
        "GI": (.init(latitude: 36.14, longitude: -5.35), 50_000),
        "IC": (.init(latitude: 28.30, longitude: -16.50), 900_000),
        "QO": (.init(latitude: -15.00, longitude: 165.00), 7_000_000),
        "TA": (.init(latitude: -37.10, longitude: -12.28), 250_000),
        "UM": (.init(latitude: 19.00, longitude: 166.00), 5_000_000)
    ]

    let polygons: [Polygon]
    private let polygonsByCode: [String: [Polygon]]

    init(resourceURL: URL?) {
        guard let url = resourceURL,
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = root["features"] as? [[String: Any]] else {
            polygons = []
            polygonsByCode = [:]
            return
        }

        var parsed: [Polygon] = []
        for feature in features {
            guard let properties = feature["properties"] as? [String: Any],
                  let code = Self.countryCode(from: properties),
                  let geometry = feature["geometry"] as? [String: Any],
                  let type = geometry["type"] as? String,
                  let coordinates = geometry["coordinates"] else { continue }

            switch type {
            case "Polygon":
                if let polygon = Self.parsePolygon(coordinates, code: code) {
                    parsed.append(polygon)
                }
            case "MultiPolygon":
                guard let values = coordinates as? [Any] else { continue }
                parsed.append(contentsOf: values.compactMap { Self.parsePolygon($0, code: code) })
            default:
                continue
            }
        }
        // Test enclaves and small territories before the countries surrounding
        // them (for example Vatican City inside Italy).
        polygons = parsed.sorted { $0.areaProxy < $1.areaProxy }
        polygonsByCode = Dictionary(grouping: polygons, by: \.code)
    }

    func countryCode(latitude: Double, longitude: Double) -> String? {
        let exact = polygons.first(where: {
            $0.contains(latitude: latitude, longitude: longitude)
        })

        // The 50m world dataset keeps tiny states visible but can place their
        // simplified outline a kilometre or two away from a real GPS point.
        // Give a very close microstate/territory precedence over the larger
        // country whose generalized outline surrounds it.
        if let tinyTerritory = polygons
            .filter({ $0.areaProxy <= 0.25 })
            .map({ ($0, $0.distanceToExteriorKilometres(latitude: latitude, longitude: longitude)) })
            .filter({ $0.1 <= 2.5 })
            .min(by: { $0.1 < $1.1 })?
            .0 {
            return tinyTerritory.code
        }

        if let exact {
            return exact.code
        }

        // A 20 km coastal tolerance recovers small islands omitted by the
        // simplified globe geometry and ordinary phone GPS drift. It is only
        // consulted when the point is not inside any country, so land-border
        // classification remains exact.
        let nearby = polygons.filter {
            latitude >= $0.minLatitude - 0.2 && latitude <= $0.maxLatitude + 0.2
                && longitude >= $0.minLongitude - 0.3 && longitude <= $0.maxLongitude + 0.3
        }
        return nearby
            .map { ($0, $0.distanceToExteriorKilometres(latitude: latitude, longitude: longitude)) }
            .filter { $0.1 <= 20 }
            .min { lhs, rhs in
                if abs(lhs.1 - rhs.1) > 0.05 { return lhs.1 < rhs.1 }
                return lhs.0.areaProxy < rhs.0.areaProxy
            }?
            .0.code
    }

    func polygons(for countryCode: String) -> [Polygon] {
        polygonsByCode[countryCode.uppercased()] ?? []
    }

    /// An offline camera target for countries without any photos. Choosing
    /// the centroid of the largest real component prevents far-flung islands
    /// from pulling the target into the ocean and avoids vertex-density bias.
    func representativeCoordinate(for countryCode: String) -> CLLocationCoordinate2D? {
        let normalized = countryCode.uppercased()
        guard let polygon = polygons(for: normalized).max(by: { $0.areaProxy < $1.areaProxy }) else {
            return Self.fallbackTargets[normalized]?.0
        }
        guard let centroid = polygon.centroid() else { return nil }
        if polygon.contains(latitude: centroid.latitude, longitude: centroid.longitude) {
            return centroid
        }

        // A mathematical centroid can fall outside a concave country or in a
        // lagoon. Find a stable interior point near an exterior edge instead.
        if let exterior = polygon.rings.first {
            for point in exterior.dropLast() {
                let candidate = Self.interpolatedCoordinate(
                    from: point,
                    toward: centroid,
                    fraction: 0.01
                )
                if polygon.contains(latitude: candidate.latitude, longitude: candidate.longitude) {
                    return candidate
                }
            }
        }
        return centroid
    }

    /// A country-sized camera range that also works for Puerto Rico and
    /// microstates instead of applying one world-scale zoom to every place.
    func suggestedCameraRange(for countryCode: String) -> CLLocationDistance {
        let normalized = countryCode.uppercased()
        let components = polygons(for: normalized)
        guard !components.isEmpty else {
            return Self.fallbackTargets[normalized]?.1 ?? 2_000_000
        }

        let largestSpanKilometres = components.map { polygon -> Double in
            let latitudeSpan = (polygon.maxLatitude - polygon.minLatitude) * 111.2
            let rawLongitudeSpan = polygon.maxLongitude - polygon.minLongitude
            let longitudeSpan = min(rawLongitudeSpan, 360 - rawLongitudeSpan)
            let middleLatitude = (polygon.minLatitude + polygon.maxLatitude) / 2
            let longitudeScale = max(cos(middleLatitude * .pi / 180), 0.15)
            return max(latitudeSpan, longitudeSpan * 111.2 * longitudeScale)
        }
        .max() ?? 1_250

        return min(7_000_000, max(30_000, largestSpanKilometres * 1_600))
    }

    func hasCameraTarget(for countryCode: String) -> Bool {
        representativeCoordinate(for: countryCode) != nil
    }

    private static func interpolatedCoordinate(
        from point: Point,
        toward target: CLLocationCoordinate2D,
        fraction: Double
    ) -> CLLocationCoordinate2D {
        var targetLongitude = target.longitude
        while targetLongitude - point.longitude > 180 { targetLongitude -= 360 }
        while targetLongitude - point.longitude < -180 { targetLongitude += 360 }
        var longitude = point.longitude + (targetLongitude - point.longitude) * fraction
        while longitude > 180 { longitude -= 360 }
        while longitude < -180 { longitude += 360 }
        return CLLocationCoordinate2D(
            latitude: point.latitude + (target.latitude - point.latitude) * fraction,
            longitude: longitude
        )
    }

    private static func countryCode(from properties: [String: Any]) -> String? {
        for key in ["ISO_A2", "ISO_A2_EH"] {
            if let value = properties[key] as? String, value.count == 2, value != "-99" {
                return value.uppercased()
            }
        }
        return nil
    }

    private static func parsePolygon(_ value: Any, code: String) -> Polygon? {
        guard let rawRings = value as? [Any] else { return nil }
        let rings = rawRings.compactMap(parseRing)
        guard let exterior = rings.first, !exterior.isEmpty else { return nil }
        let allPoints = rings.flatMap { $0 }
        return Polygon(
            code: code,
            rings: rings,
            minLatitude: allPoints.map(\.latitude).min() ?? -90,
            maxLatitude: allPoints.map(\.latitude).max() ?? 90,
            minLongitude: allPoints.map(\.longitude).min() ?? -180,
            maxLongitude: allPoints.map(\.longitude).max() ?? 180,
            areaProxy: Polygon.areaProxy(for: exterior)
        )
    }

    private static func parseRing(_ value: Any) -> [Point]? {
        guard let rawPoints = value as? [Any] else { return nil }
        let points = rawPoints.compactMap { value -> Point? in
            guard let pair = value as? [Any], pair.count >= 2,
                  let longitude = pair[0] as? NSNumber,
                  let latitude = pair[1] as? NSNumber else { return nil }
            return Point(longitude: longitude.doubleValue, latitude: latitude.doubleValue)
        }
        return points.count >= 3 ? points : nil
    }
}

/// Chooses country components that remain meaningful at the current camera
/// range. Every country keeps its largest component; visited and selected
/// countries progressively gain meaningful islands as the camera moves closer.
struct CountryPolygonLevelOfDetail {
    static func select<Component>(
        _ components: [Component],
        cameraRange: CLLocationDistance,
        includeSecondaryComponents: Bool,
        area: (Component) -> Double
    ) -> [Component] {
        let sorted = components.sorted { area($0) > area($1) }
        return selectSorted(
            sorted,
            cameraRange: cameraRange,
            includeSecondaryComponents: includeSecondaryComponents,
            area: area
        )
    }

    static func selectSorted<Component>(
        _ sorted: [Component],
        cameraRange: CLLocationDistance,
        includeSecondaryComponents: Bool,
        area: (Component) -> Double
    ) -> [Component] {
        guard includeSecondaryComponents else { return Array(sorted.prefix(1)) }
        guard let largest = sorted.first else { return [] }

        let policy = policy(for: cameraRange)
        // Absolute thresholds work well for large mainland countries, but
        // erase archipelagos whose entire geometry is small. Scale the cutoff
        // down for those countries while retaining the per-range component cap.
        let scaledMinimum = area(largest) * policy.minimumRelativeArea
        let minimumArea = min(policy.minimumAreaProxy, scaledMinimum)
        let relevant = sorted
            .filter { area($0) >= minimumArea }
            .prefix(policy.maximumCount)
        let selected = Array(relevant)
        return selected.isEmpty ? Array(sorted.prefix(1)) : selected
    }

    static func policy(
        for cameraRange: CLLocationDistance
    ) -> (minimumAreaProxy: Double, minimumRelativeArea: Double, maximumCount: Int) {
        switch cameraRange {
        case 20_000_000...:
            return (0.75, 0.025, 8)
        case 10_000_000...:
            return (0.4, 0.012, 12)
        case 3_000_000...:
            return (0.1, 0.004, 24)
        case 1_000_000...:
            return (0.01, 0.001, 48)
        default:
            return (0.002, 0.0002, 64)
        }
    }
}

/// Accumulates geographic coordinates without treating +179° and -179° as
/// opposite sides of the world.
struct GeographicCoordinateAccumulator {
    private(set) var latitudeTotal = 0.0
    private(set) var longitudeSineTotal = 0.0
    private(set) var longitudeCosineTotal = 0.0
    private(set) var count = 0

    mutating func add(latitude: Double, longitude: Double, weight: Int = 1) {
        guard weight > 0 else { return }
        let radians = longitude * .pi / 180
        latitudeTotal += latitude * Double(weight)
        longitudeSineTotal += sin(radians) * Double(weight)
        longitudeCosineTotal += cos(radians) * Double(weight)
        count += weight
    }

    var coordinate: CLLocationCoordinate2D? {
        guard count > 0 else { return nil }
        let longitude = atan2(longitudeSineTotal, longitudeCosineTotal) * 180 / .pi
        return CLLocationCoordinate2D(
            latitude: latitudeTotal / Double(count),
            longitude: longitude
        )
    }
}
