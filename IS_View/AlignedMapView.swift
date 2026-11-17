import SwiftUI
import MapKit

/// An Apple Maps view (standard or satellite) that is forced to cover exactly the same ground area, with the
/// same orientation, as the AVIRIS RGB window: same centre, same width in metres, and "up" = UTM grid north.
/// Non-interactive on purpose, so the shared touch/overlay layer in MapImageView works identically in every mode.
struct AlignedMapView: UIViewRepresentable {
    let view: ViewResult
    let satellite: Bool

    func makeUIView(context: Context) -> AlignedMKMapView {
        let m = AlignedMKMapView()
        m.isUserInteractionEnabled = false
        m.showsCompass = false
        m.showsScale = false
        m.showsUserLocation = false
        return m
    }

    func updateUIView(_ m: AlignedMKMapView, context: Context) {
        m.preferredConfiguration = satellite ? MKImageryMapConfiguration() : MKStandardMapConfiguration()
        m.target = .init(lat: view.centerLat, lon: view.centerLon, heading: view.headingDeg, widthM: view.widthM)
    }
}

final class AlignedMKMapView: MKMapView {
    struct Target: Equatable { var lat, lon, heading, widthM: Double }

    var target: Target? { didSet { if oldValue != target { setNeedsLayout(); align() } } }
    private var aligning = false
    private var alignedFor: (Target, CGSize)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        layoutMargins = .zero
        directionalLayoutMargins = .zero
        insetsLayoutMarginsFromSafeArea = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        align()
    }

    /// Set the camera, then measure how many metres span the view horizontally and rescale the camera distance
    /// until it equals the AVIRIS window width. This does not rely on MapKit's (undocumented) field of view.
    private func align() {
        guard let t = target, bounds.width > 20, bounds.height > 20, !aligning else { return }
        if let a = alignedFor, a.0 == t, a.1 == bounds.size { return }
        aligning = true; defer { aligning = false }

        let center = CLLocationCoordinate2D(latitude: t.lat, longitude: t.lon)
        var distance = t.widthM * 1.6
        for _ in 0..<6 {
            setCamera(MKMapCamera(lookingAtCenter: center, fromDistance: distance, pitch: 0, heading: t.heading),
                      animated: false)
            let l = convert(CGPoint(x: bounds.minX, y: bounds.midY), toCoordinateFrom: self)
            let r = convert(CGPoint(x: bounds.maxX, y: bounds.midY), toCoordinateFrom: self)
            let measured = CLLocation(latitude: l.latitude, longitude: l.longitude)
                .distance(from: CLLocation(latitude: r.latitude, longitude: r.longitude))
            guard measured > 1 else { break }
            let ratio = t.widthM / measured
            if abs(ratio - 1) < 2e-4 { break }
            distance *= ratio
        }
        alignedFor = (t, bounds.size)
    }
}
