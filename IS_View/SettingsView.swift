import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var m = model
        NavigationStack {
            Form {
                Section("Server (Mac, over Tailscale)") {
                    TextField("http://100.x.y.z:8765", text: $m.serverURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Text("Use the Mac's Tailscale IP or MagicDNS name and the port from config.toml.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Window half-width") {
                    Picker("Half-width", selection: $m.halfM) {
                        ForEach([250.0, 500, 1000, 2000], id: \.self) { Text("\(Int($0)) m").tag($0) }
                    }.pickerStyle(.segmented)
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
