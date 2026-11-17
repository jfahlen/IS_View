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
        default: mgr.startUpdatingLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) { start() }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        if let l = locs.last, l.horizontalAccuracy >= 0 { onFix?(l) }
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) { onStatus?("GPS: \(error.localizedDescription)") }
}
