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
            ContentRouter(model: state.app)
        }
        .css { Theme.css }
        .onAppear {
            guard !scanned else { return }
            scanned = true
            Task { await state.app.refresh() }
        }
    }
}
