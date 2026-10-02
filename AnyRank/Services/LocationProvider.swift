import CoreLocation
import Observation

/// The user's location for list maps, asked for only when a map opens.
///
/// iOS shows its permission prompt once; after that the answer lives in
/// iOS Settings, and `ListMapView` nudges with a banner when access is off.
/// The in-app "Show my location on maps" setting (`useLocationOnMaps`) sits
/// on top: when it's off, maps never ask and never use the location.
@MainActor
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {

    static let shared = LocationProvider()

    /// `@AppStorage` key for the in-app setting.
    static let useOnMapsKey = "useLocationOnMaps"

    private(set) var authorization: CLAuthorizationStatus
    private(set) var location: CLLocation?

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    /// Ask for permission the first time, or fetch a fresh fix once granted.
    func start() {
        switch authorization {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    // The manager is created on the main thread, so its callbacks arrive there.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            authorization = status
            if isAuthorized { self.manager.requestLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            if let latest = locations.last { location = latest }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // No fix (e.g. indoors, or the Simulator without a location set):
        // the map keeps its list-fitting framing.
    }
}
