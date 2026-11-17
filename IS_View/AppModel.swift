import SwiftUI
import CoreLocation

@MainActor @Observable
final class AppModel {
    // settings (persisted)
    var serverURL: String = UserDefaults.standard.string(forKey: "serverURL") ?? "http://100.x.y.z:8765" {
        didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL"); api.baseURL = serverURL; info = nil }
    }
    var halfM: Double = UserDefaults.standard.object(forKey: "halfM") as? Double ?? 500 {
        didSet { UserDefaults.standard.set(halfM, forKey: "halfM"); lastRequest = nil; if let l = lastFix { handleFix(l) } }
    }

    // state
    var info: ServerInfo?
    var view: ViewResult?
    var gpsPixel: (x: Int, y: Int)?
    var gpsSpectrum: [Int16]?
    var touchPixel: (x: Int, y: Int)?
    var touchSpectrum: [Int16]?
    var status = "Waiting for GPS…"
    var lastLatencyMs: Double?
    var accuracyM: Double?

    private var api: APIClient
    private let location = LocationService()
    private var lastFix: CLLocation?
    private var lastRequest: CLLocation?
    private var viewTask: Task<Void, Never>?
    private var cache: [PixelKey: [Int16]] = [:]
    private var pendingTouch: (x: Int, y: Int)?
    private var touchWorker: Task<Void, Never>?
    private var gpsTask: Task<Void, Never>?

    init() {
        api = APIClient(baseURL: UserDefaults.standard.string(forKey: "serverURL") ?? "http://100.x.y.z:8765")
        location.onFix = { [weak self] l in Task { @MainActor in self?.handleFix(l) } }
        location.onStatus = { [weak self] s in Task { @MainActor in self?.status = s } }
        location.start()
    }

    // MARK: GPS
    func handleFix(_ l: CLLocation) {
        lastFix = l
        accuracyM = l.horizontalAccuracy
        // Re-request the window when we leave the central part of the current one.
        let needNew = lastRequest.map { l.distance(from: $0) > 0.25 * halfM } ?? true
        if needNew && viewTask == nil { requestView(l) }
        updateGPSPixel(l)
    }

    func recenter() { if let l = lastFix { lastRequest = nil; touchPixel = nil; touchSpectrum = nil; requestView(l) } }

    private func requestView(_ l: CLLocation) {
        viewTask = Task {
            defer { viewTask = nil }
            do {
                if info == nil { info = try await api.info() }
                let t0 = Date()
                let v = try await api.view(lat: l.coordinate.latitude, lon: l.coordinate.longitude, halfM: halfM)
                lastLatencyMs = Date().timeIntervalSince(t0) * 1000
                view = v
                lastRequest = l
                status = "\(v.scene.prefix(24))…"
                if !v.centerSpectrum.isEmpty { gpsSpectrum = v.centerSpectrum
                    cache[PixelKey(scene: v.scene, x: Int(v.cx), y: Int(v.cy))] = v.centerSpectrum }
                updateGPSPixel(l)
            } catch {
                if case APIError.noCoverage = error { view = nil; gpsSpectrum = nil; gpsPixel = nil }
                status = error.localizedDescription
                lastRequest = l   // don't hammer the server while standing outside coverage
            }
        }
    }

    /// Position of the live GPS fix inside the current window (flat-earth offset from the window's request point;
    /// accurate to well under a pixel over a ~1 km window).
    private func updateGPSPixel(_ l: CLLocation) {
        guard let v = view else { return }
        let dE = (l.coordinate.longitude - v.originLon) * 111_320 * cos(v.originLat * .pi / 180)
        let dN = (l.coordinate.latitude - v.originLat) * 110_540
        let px = Int((v.cx + dE / v.pixelSize).rounded(.down)), py = Int((v.cy - dN / v.pixelSize).rounded(.down))
        if gpsPixel?.x == px && gpsPixel?.y == py { return }
        gpsPixel = (px, py)
        gpsTask?.cancel()
        gpsTask = Task {
            if let s = try? await spectrumFor(scene: v.scene, x: px, y: py) { gpsSpectrum = s }
        }
    }

    // MARK: touch (latest-wins, one request in flight)
    func touch(x: Int, y: Int) {
        guard let v = view else { return }
        if x < 0 || y < 0 { return }
        touchPixel = (x, y)
        pendingTouch = (x, y)
        guard touchWorker == nil else { return }
        touchWorker = Task {
            defer { touchWorker = nil }
            while let p = pendingTouch {
                pendingTouch = nil
                if let s = try? await spectrumFor(scene: v.scene, x: p.x, y: p.y) { touchSpectrum = s }
            }
        }
    }

    private func spectrumFor(scene: String, x: Int, y: Int) async throws -> [Int16] {
        let k = PixelKey(scene: scene, x: x, y: y)
        if let s = cache[k] { return s }
        let t0 = Date()
        let s = try await api.spectrum(scene: scene, x: x, y: y)
        lastLatencyMs = Date().timeIntervalSince(t0) * 1000
        if cache.count > 3000 { cache.removeAll(keepingCapacity: true) }
        cache[k] = s
        return s
    }
}
