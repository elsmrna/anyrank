import MapKit

/// Where a list's map opens, and how its pins stack.
enum MapFraming {

    /// "Nearby" for framing: 5 miles.
    static let nearbyRadius: CLLocationDistance = 8_047

    /// The region a list's map opens on. Centers on the user with 5 miles
    /// in every direction when at least one pin is within 5 miles of them;
    /// otherwise fits every pin. Nil when there are no pins.
    static func initialRegion(pins: [CLLocationCoordinate2D], user: CLLocationCoordinate2D?) -> MKCoordinateRegion? {
        guard !pins.isEmpty else { return nil }
        if let user, hasPin(pins, within: nearbyRadius, of: user) {
            return MKCoordinateRegion(center: user, latitudinalMeters: nearbyRadius * 2, longitudinalMeters: nearbyRadius * 2)
        }
        return fitting(pins)
    }

    static func hasPin(_ pins: [CLLocationCoordinate2D], within radius: CLLocationDistance, of point: CLLocationCoordinate2D) -> Bool {
        let here = CLLocation(latitude: point.latitude, longitude: point.longitude)
        return pins.contains { here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <= radius }
    }

    /// A region showing every pin with some breathing room, and no tighter
    /// than about 2 km so a single pin isn't shown at street level.
    static func fitting(_ pins: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let lats = pins.map(\.latitude), lons = pins.map(\.longitude)
        let (minLat, maxLat) = (lats.min()!, lats.max()!)
        let (minLon, maxLon) = (lons.min()!, lons.max()!)
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.35, 0.02),
            longitudeDelta: max((maxLon - minLon) * 1.35, 0.02)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    /// Stacking order for a pin: rank 1 draws above everything else.
    static func zPriority(forRank rank: Int, of total: Int) -> MKAnnotationViewZPriority {
        let fraction = total > 1 ? Float(total - rank) / Float(total - 1) : 1
        return MKAnnotationViewZPriority(rawValue: 900 * min(max(fraction, 0), 1))
    }
}
