import UIKit

enum APIError: LocalizedError {
    case badURL, noCoverage(String), http(Int), decode
    var errorDescription: String? {
        switch self {
        case .badURL: return "Bad server URL"
        case .noCoverage(let s): return s
        case .http(let c): return "Server error \(c)"
        case .decode: return "Bad response"
        }
    }
}

final class APIClient {
    var baseURL: String
    private let session: URLSession

    init(baseURL: String) {
        self.baseURL = baseURL
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.httpMaximumConnectionsPerHost = 4
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: cfg)
    }

    private func url(_ path: String, _ q: [String: String]) throws -> URL {
        guard var c = URLComponents(string: baseURL.trimmingCharacters(in: .whitespaces) + path) else { throw APIError.badURL }
        c.queryItems = q.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let u = c.url else { throw APIError.badURL }
        return u
    }

    func info() async throws -> ServerInfo {
        let (d, r) = try await session.data(from: url("/info", [:]))
        try check(r)
        return try JSONDecoder().decode(ServerInfo.self, from: d)
    }

    func view(lat: Double, lon: Double, halfM: Double) async throws -> ViewResult {
        let (d, r) = try await session.data(from: url("/view", ["lat": "\(lat)", "lon": "\(lon)", "half_m": "\(halfM)"]))
        if let h = r as? HTTPURLResponse, h.statusCode == 404 {
            let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
            var msg = "No data here"
            if let dist = j?["distance_m"] as? Double { msg += String(format: " (nearest scene %.1f km away)", dist / 1000) }
            throw APIError.noCoverage(msg)
        }
        try check(r)
        guard let h = r as? HTTPURLResponse, let img = UIImage(data: d) else { throw APIError.decode }
        func hdr(_ k: String) -> String { h.value(forHTTPHeaderField: k) ?? "" }
        guard let px0 = Int(hdr("X-Px0")), let py0 = Int(hdr("X-Py0")), let w = Int(hdr("X-W")), let ht = Int(hdr("X-H")),
              let sc = Int(hdr("X-Scale")), let cx = Double(hdr("X-Cx")), let cy = Double(hdr("X-Cy")),
              let ps = Double(hdr("X-Pixel-Size")),
              let clat = Double(hdr("X-Center-Lat")), let clon = Double(hdr("X-Center-Lon")),
              let hdg = Double(hdr("X-Heading")) else { throw APIError.decode }
        let spec = Data(base64Encoded: hdr("X-Center-Spectrum")).map(Self.int16s) ?? []
        return ViewResult(image: img, scene: hdr("X-Scene"), px0: px0, py0: py0, w: w, h: ht, scale: sc, cx: cx, cy: cy,
                          pixelSize: ps, centerSpectrum: spec, serverMs: Double(hdr("X-Server-Ms")) ?? 0,
                          originLat: lat, originLon: lon,
                          centerLat: clat, centerLon: clon, headingDeg: hdg)
    }

    func spectrum(scene: String, x: Int, y: Int) async throws -> [Int16] {
        let (d, r) = try await session.data(from: url("/spectrum", ["scene": scene, "x": "\(x)", "y": "\(y)"]))
        try check(r)
        return Self.int16s(d)
    }

    private func check(_ r: URLResponse) throws {
        if let h = r as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw APIError.http(h.statusCode) }
    }

    static func int16s(_ d: Data) -> [Int16] {
        d.withUnsafeBytes { raw in
            (0..<d.count / 2).map { Int16(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 2, as: Int16.self)) }
        }
    }
}
