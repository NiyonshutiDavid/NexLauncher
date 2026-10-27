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
        .dialog(visible: Binding(get: { state.app.showOnboarding }, set: { if !$0 { state.app.skipOnboarding(); Task { await state.app.refresh() } } }),
                title: "Welcome", width: 560, height: 460) {
            OnboardingContent(model: state.app)
        }
        .dialog(visible: Binding(get: { state.app.pendingQuitSummary != nil }, set: { if !$0 { state.app.pendingQuitSummary = nil } }),
                title: "Quit NexLauncher?", width: 420, height: 220) {
            QuitDialogContent(model: state.app) { window.close() }
        }
        .css { Theme.css }
        .onAppear {
            guard !scanned else { return }
            scanned = true
            Shared.terminals.onChange = { state.setModel { $0.tick &+= 1 } }
            Shared.services.presentMainWindow = { gtk_window_present(window.pointer?.cast()); return true }
            // Notifications are only posted while the window isn't focused (unless the user turns that off).
            Shared.services.windowIsActive = { gtk_window_is_active(window.pointer?.cast()) != 0 }
            Task {
                // Tools from nvm, pyenv, asdf… are only on the interactive shell's PATH: read it once first.
                HostCommand.setUserEnvironment(await ShellEnvironment.capture(shell: HostCommand.defaultShell,
                                                                              flatpak: Platform.isFlatpak))
                // On first launch the projects folder is chosen in onboarding, which scans it when it finishes.
                if !state.app.showOnboarding { await state.app.refresh() }
            }
        }
    }

    func window(_ window: Window) -> Window { window }
}
