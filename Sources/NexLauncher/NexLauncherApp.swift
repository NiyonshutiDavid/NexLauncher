import SwiftUI
import NexUI

@main
struct NexLauncherApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("NexLauncher", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 860, minHeight: 560)
                .task { await model.refresh() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }
}
