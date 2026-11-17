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

    /// nil = Auto (server picks the best scene covering the fix); otherwise a scene id from /info.
    var selectedScene: String? = UserDefaults.standard.string(forKey: "selectedScene") {
        didSet {
            guard selectedScene != oldValue else { return }
            UserDefaults.standard.set(selectedScene, forKey: "selectedScene")
            switchScene()
        }
    }

    // state
    var covering: [String] = []          // scenes with data at the current fix (from the server)
    var displayMode: DisplayMode = .image
    var info: ServerInfo?
    var view: ViewResult?
    var gpsPixel: (x: Int, y: Int)?
    var gpsSpectrum: [Int16]?
    var touchPixel: (x: Int, y: Int)?
    var touchSpectrum: [Int16]?
    var status = "Waiting for GPS…"
    var lastLatencyMs: Double?
    var accuracyM: Double?

    /// Wavelengths of the scene currently shown (scenes differ: AVIRIS-3 has 284 bands, AVIRIS-5 424).
    var currentWavelengths: [Double] {
        guard let id = view?.scene else { return [] }
        return info?.scenes.first { $0.scene == id }?.wavelengths ?? []
    }
    var currentSceneLabel: String? {
        guard let id = view?.scene else { return nil }
        return info?.scenes.first { $0.scene == id }?.label ?? id
    }

    private var needInfoRefresh = false
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

    func recenter() {
        needInfoRefresh = true                    // also picks up scenes added to the server since launch
        if let l = lastFix { lastRequest = nil; touchPixel = nil; touchSpectrum = nil; requestView(l) }
    }

    private func switchScene() {
        touchPixel = nil; touchSpectrum = nil; gpsSpectrum = nil
        lastRequest = nil
        viewTask?.cancel(); viewTask = nil
        if let l = lastFix { requestView(l) }
    }

    private func requestView(_ l: CLLocation) {
        viewTask = Task {
            defer { if !Task.isCancelled { viewTask = nil } }
            do {
                if info == nil || needInfoRefresh { info = try await api.info(); needInfoRefresh = false }
                let t0 = Date()
                // With an explicit scene we allow a "preview" around the scene's centre when the fix is outside it.
                let v = try await api.view(lat: l.coordinate.latitude, lon: l.coordinate.longitude, halfM: halfM,
                                           scene: selectedScene, preview: selectedScene != nil)
                if Task.isCancelled { return }
                lastLatencyMs = Date().timeIntervalSince(t0) * 1000
                if view?.scene != v.scene { touchPixel = nil; touchSpectrum = nil; gpsSpectrum = nil }
                view = v
                covering = v.covering
                lastRequest = l
                status = (currentSceneLabel ?? v.scene) + (v.preview ? " — preview (you're outside this scene)" : "")
                cache[PixelKey(scene: v.scene, x: Int(v.cx), y: Int(v.cy))] = v.centerSpectrum
                if v.preview {
                    // Not at the user's location: show the scene-centre spectrum as the "touched" point instead.
                    gpsPixel = nil; gpsSpectrum = nil
                    touchPixel = (Int(v.cx), Int(v.cy)); touchSpectrum = v.centerSpectrum
                } else {
                    if !v.centerSpectrum.isEmpty { gpsSpectrum = v.centerSpectrum }
                    updateGPSPixel(l)
                }
            } catch {
                if Task.isCancelled || error is CancellationError { return }
                if case APIError.noCoverage(_, let cov) = error {
                    view = nil; gpsSpectrum = nil; gpsPixel = nil; touchPixel = nil; touchSpectrum = nil; covering = cov
                }
                status = error.localizedDescription
                lastRequest = l   // don't hammer the server while standing outside coverage
            }
        }
    }

    /// Position of the live GPS fix inside the current window, using the exact window geometry
    /// (including grid-north rotation) so it lines up with the map layers.
    private func updateGPSPixel(_ l: CLLocation) {
        guard let v = view, !v.preview else { return }
        let p = v.pixel(for: l.coordinate)
        let px = Int(p.x.rounded(.down)), py = Int(p.y.rounded(.down))
        guard px >= v.px0, px < v.px0 + v.w, py >= v.py0, py < v.py0 + v.h else { gpsPixel = nil; return }
        if gpsPixel?.x == px && gpsPixel?.y == py { return }
        gpsPixel = (px, py)
        gpsTask?.cancel()
        gpsTask = Task {
            if let s = try? await spectrumFor(scene: v.scene, x: px, y: py), view?.scene == v.scene { gpsSpectrum = s }
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
