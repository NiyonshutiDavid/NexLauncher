import Foundation
import Adwaita
import CAdw
import NexApp

/// Opens a URI with the user's default app.
@MainActor
protocol URILaunching {
    func launch(uri: String)
}

/// GLib's launcher: uses the desktop's default handler, and the OpenURI portal inside a Flatpak.
@MainActor
struct GLibLauncher: URILaunching {
    func launch(uri: String) { _ = g_app_info_launch_default_for_uri(uri, nil, nil) }
}

/// The Linux side of `PlatformServices`. There is no Dock and no WidgetKit; apps are opened by URI.
@MainActor
final class LinuxPlatformServices: PlatformServices {
    let launcher: URILaunching
    /// Set by the window: presents it and says whether it exists.
    var presentMainWindow: () -> Bool = { false }
    var windowIsActive: () -> Bool = { true }

    init(launcher: URILaunching = GLibLauncher()) {
        self.launcher = launcher
    }

    func open(_ url: URL) { launcher.launch(uri: url.absoluteString) }

    /// File managers differ; opening the containing folder works everywhere.
    func reveal(_ path: URL) { launcher.launch(uri: path.deletingLastPathComponent().absoluteString) }

    func copy(_ text: String) { AdwaitaApp.copy(text) }

    func open(_ files: [URL], withApplicationAt app: URL) { files.forEach(open) }

    @discardableResult
    func activateMainWindow() -> Bool { presentMainWindow() }

    func reloadWidgets() {}
    func setDockIconVisible(_ visible: Bool) {}
    var isAppActive: Bool { windowIsActive() }
}
