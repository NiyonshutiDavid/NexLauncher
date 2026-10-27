import Foundation
import Adwaita
import NexApp
import NexCore

/// One model for the whole app (the Linux counterpart of the Mac app delegate's).
@MainActor
enum Shared {
    static let services = LinuxPlatformServices()
    static let model = AppModel(services: services, terminals: PendingTerminalHost())
}

@main
struct NexLauncherLinux: App {
    let app = AdwaitaApp(id: "net.nexventures.NexLauncher")

    var scene: Scene {
        Window(id: "main") { window in
            MainWindow(app: app, window: window)
        }
        .defaultSize(width: 1200, height: 800)
        .title("NexLauncher")
    }
}

/// Until the VTE terminal lands, tabs are remembered so the model behaves the same.
@MainActor
final class PendingTerminalHost: TerminalHost {
    private(set) var tabs: [(id: UUID, directory: URL, command: String?)] = []
    var hasRunningPrograms: Bool { false }
    @discardableResult func openTab(at directory: URL, command: String?) -> UUID {
        let id = UUID()
        tabs.append((id, directory, command))
        return id
    }
    func close(_ id: UUID) { tabs.removeAll { $0.id == id } }
    func closeAll() { tabs.removeAll() }
}
