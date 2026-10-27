import Foundation
import Adwaita
import CAdw
import CVte
import NexApp
import NexCore

/// Terminal tabs backed by VTE widgets, kept alive while their tab is open.
@MainActor
final class LinuxTerminalHost: TerminalHost {
    struct Tab: Identifiable { let id: UUID; let directory: URL; let widget: UnsafeMutableRawPointer }
    private(set) var tabs: [Tab] = []
    var selectedID: UUID?
    /// Lets the window re-render when tabs change.
    var onChange: () -> Void = {}

    /// VTE can't tell which programs run in a tab without more plumbing; quitting doesn't warn about tabs yet.
    var hasRunningPrograms: Bool { false }

    @discardableResult
    func openTab(at directory: URL, command: String?) -> UUID {
        guard let widget = vte_terminal_new() else { return UUID() }
        _ = g_object_ref_sink(widget)             // owned here, not by whichever view shows it
        let shell = HostCommand.defaultShell
        var argv: [String]
        if Platform.isFlatpak {
            argv = [HostCommand.flatpakSpawn, "--host", "--watch-bus", "--directory=\(directory.path)",
                    "--env=TERM=xterm-256color", shell, "-l"]
        } else {
            argv = [shell, "-l"]
        }
        withCStrings(argv) { cArgv in
            vte_terminal_spawn_async(widget, 0, directory.path, cArgv, nil, 0, nil, nil, nil, -1, nil, nil, nil)
        }
        if let command { feed(widget, command + "\n") }
        let tab = Tab(id: UUID(), directory: directory, widget: widget)
        tabs.append(tab)
        selectedID = tab.id
        onChange()
        return tab.id
    }

    func close(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        g_object_unref(tabs[index].widget)
        tabs.remove(at: index)
        if selectedID == id { selectedID = tabs.last?.id }
        onChange()
    }

    func closeAll() { tabs.map(\.id).forEach(close) }

    private func feed(_ widget: UnsafeMutableRawPointer, _ text: String) {
        text.withCString { vte_terminal_feed_child(widget, $0, Int(strlen($0))) }
    }

    private func withCStrings(_ strings: [String], _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Void) {
        var pointers: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) } + [nil]
        defer { pointers.forEach { free($0) } }
        pointers.withUnsafeMutableBufferPointer { body($0.baseAddress!) }
    }
}

/// Shows one VTE terminal widget.
struct VteView: AdwaitaWidget {
    let widget: UnsafeMutableRawPointer

    func container<Data>(data: WidgetData, type: Data.Type) -> ViewStorage where Data: ViewRenderData {
        .init(OpaquePointer(widget))
    }

    func update<Data>(_ storage: ViewStorage, data: WidgetData, updateProperties: Bool, type: Data.Type) where Data: ViewRenderData {}
}

/// The Terminal tab: tabs for this project's folder and a new-tab button.
struct TerminalTab: View {
    let model: AppModel
    let directory: URL

    private var host: LinuxTerminalHost? { model.terminals as? LinuxTerminalHost }

    var view: Body {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(host?.tabs ?? []) { tab in
                    Button(tab.directory.lastPathComponent) { host?.selectedID = tab.id; host?.onChange() }
                        .flat()
                }
                Button(icon: .default(icon: .listAdd)) { model.openTerminal(at: directory) }.flat().tooltip("New terminal tab")
                if let id = host?.selectedID {
                    Button(icon: .custom(name: "window-close-symbolic")) { host?.close(id) }.flat().tooltip("Close this tab")
                }
            }
            .halign(.start)
            if let host, let tab = host.tabs.first(where: { $0.id == host.selectedID }) {
                VteView(widget: tab.widget).vexpand().hexpand().frame(minHeight: 420)
            } else {
                Button("Open a terminal here") { model.openTerminal(at: directory) }.pill().halign(.center).padding(24)
            }
        }
    }
}
