import Foundation
import Adwaita
import NexApp
import NexCore

/// One model for the whole app (the Linux counterpart of the Mac app delegate's).
@MainActor
enum Shared {
    static let app = AdwaitaApp(id: "net.nexventures.NexLauncher")
    static let services = LinuxPlatformServices()
    static let terminals = LinuxTerminalHost()
    static let model = AppModel(services: services, terminals: terminals, notifier: LinuxNotifier(app: app))
}

@main
struct NexLauncherLinux: App {
    let app = Shared.app

    var scene: Scene {
        Window(id: "main") { window in
            MainWindow(app: app, window: window)
        }
        .defaultSize(width: 1200, height: 800)
        .title("NexLauncher")
    }
}
