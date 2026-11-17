import SwiftUI
import MapKit

/// Apple "Look Around" (street-level imagery) at a coordinate. Tap it to open the full-screen experience.
struct LookAroundCard: View {
    let coordinate: CLLocationCoordinate2D
    @State private var scene: MKLookAroundScene?
    @State private var searching = true

    var body: some View {
        ZStack {
            if scene != nil {
                LookAroundPreview(scene: $scene, allowsNavigation: true, badgePosition: .bottomTrailing)
            } else {
                Color(.secondarySystemBackground)
                Text(searching ? "Looking for street view…" : "No street view here")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.8), lineWidth: 1.5))
        .shadow(radius: 4)
        // Re-query (debounced) as the selected point moves; ~10 m granularity is plenty for street imagery.
        .task(id: "\(Int(coordinate.latitude * 10_000)),\(Int(coordinate.longitude * 10_000))") {
            searching = true
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            let found = try? await MKLookAroundSceneRequest(coordinate: coordinate).scene
            if Task.isCancelled { return }
            scene = found
            searching = false
        }
    }
}
