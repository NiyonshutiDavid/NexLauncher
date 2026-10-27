import Foundation
import Adwaita
import CAdw
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
        .dialog(visible: Binding(get: { state.app.setup != nil }, set: { if !$0 { state.app.cancelInstall() } }),
                title: "Set up", width: 520, height: 420) {
            SetupDialogContent(model: state.app)
        }
        .dialog(visible: Binding(get: { state.app.sheet != nil }, set: { if !$0 { state.app.sheet = nil } }),
                title: "Add project", width: 520, height: 460) {
            AddProjectDialogContent(model: state.app, mode: {
                if case .addProject(let mode) = state.app.sheet { return mode }
                return .newFolder
            }())
        }
        .dialog(visible: Binding(get: { state.app.showOnboarding }, set: { if !$0 { state.app.skipOnboarding() } }),
                title: "Welcome", width: 560, height: 460) {
            OnboardingContent(model: state.app)
        }
        .css { Theme.css }
        .onAppear {
            guard !scanned else { return }
            scanned = true
            Shared.terminals.onChange = { state.setModel { $0.tick &+= 1 } }
            Shared.services.presentMainWindow = { gtk_window_present(window.pointer?.cast()); return true }
            Task { await state.app.refresh() }
        }
    }

    func window(_ window: Window) -> Window { window }
}
