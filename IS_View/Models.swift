import UIKit

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
