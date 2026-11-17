import SwiftUI
import Charts

struct SpectrumView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let wl = model.info?.wavelengths ?? []
        let gps = model.gpsSpectrum.map { spectrumPoints(series: "GPS", wavelengths: wl, values: $0.reflectance) } ?? []
        let touch = model.touchSpectrum.map { spectrumPoints(series: "Touch", wavelengths: wl, values: $0.reflectance) } ?? []
        let all = gps + touch
        let ymax = max(0.1, (all.map(\.value).max() ?? 0.1) * 1.1)
        let ymin = min(0, (all.map(\.value).min() ?? 0) * 1.1)
        VStack(alignment: .leading, spacing: 4) {
            Chart(all) { p in
                LineMark(x: .value("Wavelength (nm)", p.wavelength), y: .value("Reflectance", p.value),
                         series: .value("seg", "\(p.series)\(p.segment)"))
                    .foregroundStyle(by: .value("Source", p.series))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            .chartForegroundStyleScale(["GPS": Color.blue, "Touch": Color.red])
            .chartXScale(domain: 350...2500)
            .chartYScale(domain: ymin...ymax)
            .chartXAxisLabel("Wavelength (nm)")
            .chartYAxisLabel("Reflectance")
            .overlay { if all.isEmpty { Text("No spectrum").foregroundStyle(.secondary) } }
            HStack(spacing: 12) {
                if let g = model.gpsPixel { Label("GPS px \(g.x),\(g.y)", systemImage: "circle.fill").foregroundStyle(.blue) }
                if let t = model.touchPixel { Label("Touch px \(t.x),\(t.y)", systemImage: "plus").foregroundStyle(.red) }
                Spacer()
                if let ms = model.lastLatencyMs { Text("\(Int(ms)) ms").foregroundStyle(.secondary) }
            }.font(.caption2)
        }
    }
}
