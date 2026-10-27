import Foundation
import Adwaita
import NexApp
import NexCore

struct MainWindow: WindowView {
    var app: AdwaitaApp
    var window: AdwaitaWindow
    @State private var state = AppState(app: Shared.model)
    @State private var scanned = false

    var view: Body {
        NavigationSplitView {
            Sidebar(model: state.app)
        } content: {
            StatusPage("NexLauncher", icon: .default(icon: .folder), description: "\(state.app.projects.count) projects") {}
        }
        .css { Theme.css }
        .onAppear {
            guard !scanned else { return }
            scanned = true
            Task { await state.app.refresh() }
        }
    }
}
