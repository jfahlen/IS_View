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
