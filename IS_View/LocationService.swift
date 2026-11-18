import CoreLocation

final class LocationService: NSObject, CLLocationManagerDelegate {
    private let mgr = CLLocationManager()
    var onFix: ((CLLocation) -> Void)?
    var onStatus: ((String) -> Void)?

    override init() {
        super.init()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyBest
        mgr.distanceFilter = 2          // metres; AVIRIS pixels are ~4-11 m
    }

    func start() {
        switch mgr.authorizationStatus {
        case .notDetermined: mgr.requestWhenInUseAuthorization()
        case .denied, .restricted: onStatus?("Location permission denied (Settings > IS View)")
        default:
            mgr.startUpdatingLocation()
            // A stationary phone may not deliver a new fix for a while: start from the last known one if it is recent.
            if let l = mgr.location, l.horizontalAccuracy >= 0, abs(l.timestamp.timeIntervalSinceNow) < 120 { onFix?(l) }
        }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) { start() }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        if let l = locs.last, l.horizontalAccuracy >= 0 { onFix?(l) }
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) { onStatus?("GPS: \(error.localizedDescription)") }
}
