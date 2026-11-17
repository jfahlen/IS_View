import UIKit
import CoreLocation

struct ServerInfo: Decodable {
    struct View: Decodable { let half_m_default: Double; let half_m_max: Double }
    let wavelengths: [Double]
    let view: View
}

/// Result of GET /view. Scene pixel of image point (ix, iy) = (px0 + ix/scale, py0 + iy/scale).
struct ViewResult {
    let image: UIImage
    let scene: String
    let px0: Int, py0: Int, w: Int, h: Int, scale: Int
    let cx: Double, cy: Double          // fix location in scene pixel coords
    let pixelSize: Double               // metres
    let centerSpectrum: [Int16]
    let serverMs: Double
    let originLat: Double, originLon: Double   // the fix this window was requested for
    let centerLat: Double, centerLon: Double   // geographic centre of the image window
    let headingDeg: Double                     // compass bearing of image "up" (UTM grid north), clockwise from true north
}

/// How the main display is rendered. Every mode covers exactly the same ground area as the AVIRIS RGB image.
enum DisplayMode: String, CaseIterable, Identifiable {
    case image = "AVIRIS", map = "Map", satellite = "Satellite", street = "Street View"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .image: return "photo"
        case .map: return "map"
        case .satellite: return "globe.americas"
        case .street: return "binoculars"
        }
    }
}

extension ViewResult {
    /// Window centre in scene pixel (edge) coordinates.
    var winCx: Double { Double(px0) + Double(w) / 2 }
    var winCy: Double { Double(py0) + Double(h) / 2 }
    var widthM: Double { Double(w) * pixelSize }
    var heightM: Double { Double(h) * pixelSize }

    /// WGS84 metres per degree of latitude / longitude at a latitude.
    private static func metresPerDegree(_ lat: Double) -> (lat: Double, lon: Double) {
        let p = lat * .pi / 180
        return (111132.92 - 559.82 * cos(2 * p) + 1.175 * cos(4 * p),
                111412.84 * cos(p) - 93.5 * cos(3 * p) + 0.118 * cos(5 * p))
    }

    /// Scene pixel (fractional, edge coords) -> geographic coordinate. Accounts for the grid-north rotation.
    func coordinate(px: Double, py: Double) -> CLLocationCoordinate2D {
        let hr = headingDeg * .pi / 180, m = Self.metresPerDegree(centerLat)
        let ex = (px - winCx) * pixelSize, ny = -(py - winCy) * pixelSize
        let dE = ex * cos(hr) + ny * sin(hr), dN = -ex * sin(hr) + ny * cos(hr)
        return CLLocationCoordinate2D(latitude: centerLat + dN / m.lat, longitude: centerLon + dE / m.lon)
    }

    /// Geographic coordinate -> scene pixel (fractional, edge coords).
    func pixel(for c: CLLocationCoordinate2D) -> (x: Double, y: Double) {
        let hr = headingDeg * .pi / 180, m = Self.metresPerDegree(centerLat)
        let dE = (c.longitude - centerLon) * m.lon, dN = (c.latitude - centerLat) * m.lat
        let ex = dE * cos(hr) - dN * sin(hr), ny = dE * sin(hr) + dN * cos(hr)
        return (winCx + ex / pixelSize, winCy - ny / pixelSize)
    }
}

struct PixelKey: Hashable { let scene: String; let x: Int; let y: Int }

enum Nodata { static let value: Int16 = -32768 }

extension Array where Element == Int16 {
    /// int16 * 1e-4 -> reflectance; nil where nodata.
    var reflectance: [Double?] { map { $0 == Nodata.value ? nil : Double($0) / 10000.0 } }
}

struct SpectrumPoint: Identifiable {
    let id: Int
    let series: String
    let segment: Int
    let wavelength: Double
    let value: Double
}

/// Build chart points, splitting into contiguous segments so nodata bands leave gaps.
func spectrumPoints(series: String, wavelengths: [Double], values: [Double?]) -> [SpectrumPoint] {
    var out: [SpectrumPoint] = []
    var seg = 0
    var lastValid = false
    for (i, v) in values.enumerated() where i < wavelengths.count {
        if let v {
            if !lastValid && !out.isEmpty { seg += 1 }
            out.append(SpectrumPoint(id: i, series: series, segment: seg, wavelength: wavelengths[i], value: v))
            lastValid = true
        } else { lastValid = false }
    }
    return out
}
