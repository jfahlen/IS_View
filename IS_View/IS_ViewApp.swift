import SwiftUI

@main
struct IS_ViewApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            ContentView().environment(model)
        }
    }
}
