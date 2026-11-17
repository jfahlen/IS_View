import SwiftUI

/// Shows the RGB window; blue dot = GPS location, red crosshair = touched pixel. Touch/drag picks a scene pixel.
struct MapImageView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { geo in
            if let v = model.view {
                let imgW = Double(v.w * v.scale), imgH = Double(v.h * v.scale)
                let k = min(geo.size.width / imgW, geo.size.height / imgH)         // image px -> points
                let ox = (geo.size.width - imgW * k) / 2, oy = (geo.size.height - imgH * k) / 2
                let pt: (Int, Int) -> CGPoint = { sx, sy in
                    CGPoint(x: ox + (Double(sx - v.px0) + 0.5) * Double(v.scale) * k,
                            y: oy + (Double(sy - v.py0) + 0.5) * Double(v.scale) * k)
                }
                ZStack {
                    Group {
                        switch model.displayMode {
                        case .image:
                            Image(uiImage: v.image).resizable().interpolation(.high)
                        case .map, .street:
                            AlignedMapView(view: v, satellite: false)
                        case .satellite:
                            AlignedMapView(view: v, satellite: true)
                        }
                    }
                    .frame(width: imgW * k, height: imgH * k)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    if model.displayMode == .street {
                        let sel = model.touchPixel ?? model.gpsPixel
                        let c = sel.map { v.coordinate(px: Double($0.x) + 0.5, py: Double($0.y) + 0.5) }
                            ?? v.coordinate(px: v.winCx, py: v.winCy)
                        LookAroundCard(coordinate: c)
                            .frame(width: imgW * k * 0.55, height: imgH * k * 0.34)
                            .position(x: ox + imgW * k * 0.275 + 8, y: oy + imgH * k * 0.17 + 8)
                    }
                    if let g = model.gpsPixel {
                        Circle().fill(.blue).frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .position(pt(g.x, g.y))
                    }
                    if let t = model.touchPixel {
                        Crosshair().stroke(.red, lineWidth: 2).frame(width: 28, height: 28).position(pt(t.x, t.y))
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    let ix = (g.location.x - ox) / k, iy = (g.location.y - oy) / k
                    guard ix >= 0, iy >= 0, ix < imgW, iy < imgH else { return }
                    model.touch(x: v.px0 + Int(ix) / v.scale, y: v.py0 + Int(iy) / v.scale)
                })
            } else {
                ZStack { Color(.secondarySystemBackground); Text(model.status).multilineTextAlignment(.center).padding() }
            }
        }
    }
}

struct Crosshair: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return p
    }
}
