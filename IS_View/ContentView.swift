import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text("IS View").font(.headline)
                    Text(model.status).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if let a = model.accuracyM { Text("±\(Int(a)) m").font(.caption).foregroundStyle(.secondary) }
                @Bindable var m = model
                if let scenes = model.info?.scenes, scenes.count > 0 {
                    Menu {
                        Picker("Dataset", selection: $m.selectedScene) {
                            Text("Auto (best at my location)").tag(String?.none)
                            ForEach(scenes) { sc in
                                let here = model.covering.contains(sc.scene)
                                Label(sc.label + (here ? "" : " — not at my location"),
                                      systemImage: here ? "location.fill" : "location.slash")
                                    .tag(Optional(sc.scene))
                            }
                        }
                    } label: { Image(systemName: "square.stack.3d.up") }
                }
                Menu {
                    Picker("Display", selection: $m.displayMode) {
                        ForEach(DisplayMode.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                    }
                } label: { Image(systemName: model.displayMode.icon) }
                Button { model.recenter() } label: { Image(systemName: "location.fill") }
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
            .padding(.horizontal)
            MapImageView().frame(maxHeight: .infinity).clipped()
            SpectrumView().frame(height: 240).padding(.horizontal)
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showSettings) { SettingsView() }
    }
}
