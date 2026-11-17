import SwiftUI
import Charts

struct SpectrumView: View {
    @Environment(AppModel.self) private var model

    private static let full: ClosedRange<Double> = 350...2500
    private static let minSpan = 40.0                       // nm: max zoom

    @State private var xRange = SpectrumView.full
    @State private var panBase: ClosedRange<Double>?
    @State private var zoomBase: ClosedRange<Double>?

    private var isZoomed: Bool { xRange != Self.full }

    var body: some View {
        let wl = model.info?.wavelengths ?? []
        let gps = model.gpsSpectrum.map { spectrumPoints(series: "GPS", wavelengths: wl, values: $0.reflectance) } ?? []
        let touch = model.touchSpectrum.map { spectrumPoints(series: "Touch", wavelengths: wl, values: $0.reflectance) } ?? []
        let all = gps + touch
        // Fit the y axis to what is currently visible.
        let visible = all.filter { xRange.contains($0.wavelength) }.map(\.value)
        let vmax = visible.max() ?? 0.1, vmin = visible.min() ?? 0
        let pad = max(0.02, (vmax - vmin) * 0.08)
        let ymax = vmax + pad
        let ymin = isZoomed ? vmin - pad : min(0, vmin - pad)

        VStack(alignment: .leading, spacing: 4) {
            Chart(all) { p in
                LineMark(x: .value("Wavelength (nm)", p.wavelength), y: .value("Reflectance", p.value),
                         series: .value("seg", "\(p.series)\(p.segment)"))
                    .foregroundStyle(by: .value("Source", p.series))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            .chartForegroundStyleScale(["GPS": Color.blue, "Touch": Color.red])
            .chartXScale(domain: xRange)
            .chartYScale(domain: ymin...ymax)
            .chartXAxisLabel("Wavelength (nm)")
            .chartYAxisLabel("Reflectance")
            .chartPlotStyle { $0.clipped() }
            .overlay { if all.isEmpty { Text("No spectrum").foregroundStyle(.secondary) } }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    let plot = proxy.plotFrame.map { geo[$0] } ?? CGRect(origin: .zero, size: geo.size)
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(panGesture(plot: plot).simultaneously(with: zoomGesture(plot: plot)))
                        .onTapGesture(count: 2) { withAnimation(.easeOut(duration: 0.2)) { xRange = Self.full } }
                }
            }
            HStack(spacing: 12) {
                if let g = model.gpsPixel { Label("GPS px \(g.x),\(g.y)", systemImage: "circle.fill").foregroundStyle(.blue) }
                if let t = model.touchPixel { Label("Touch px \(t.x),\(t.y)", systemImage: "plus").foregroundStyle(.red) }
                Spacer()
                if isZoomed { Text("\(Int(xRange.lowerBound))–\(Int(xRange.upperBound)) nm · double-tap to reset").foregroundStyle(.secondary) }
                else if let ms = model.lastLatencyMs { Text("\(Int(ms)) ms").foregroundStyle(.secondary) }
            }.font(.caption2)
        }
    }

    // MARK: gestures

    private func panGesture(plot: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                let base = panBase ?? xRange
                panBase = base
                let span = base.upperBound - base.lowerBound
                let dx = -Double(v.translation.width / max(plot.width, 1)) * span
                xRange = Self.clamp(lo: base.lowerBound + dx, span: span)
            }
            .onEnded { _ in panBase = nil }
    }

    private func zoomGesture(plot: CGRect) -> some Gesture {
        MagnifyGesture()
            .onChanged { v in
                let base = zoomBase ?? xRange
                zoomBase = base
                let span0 = base.upperBound - base.lowerBound
                let span = min(max(span0 / Double(v.magnification), Self.minSpan),
                               Self.full.upperBound - Self.full.lowerBound)
                // Keep the wavelength under the pinch centre fixed on screen.
                let f = Double(min(max((v.startLocation.x - plot.minX) / max(plot.width, 1), 0), 1))
                let anchor = base.lowerBound + f * span0
                xRange = Self.clamp(lo: anchor - f * span, span: span)
            }
            .onEnded { _ in zoomBase = nil }
    }

    private static func clamp(lo: Double, span: Double) -> ClosedRange<Double> {
        let l = min(max(lo, full.lowerBound), full.upperBound - span)
        return l...(l + span)
    }
}
