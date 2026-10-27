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
        // The command (an agent, a sign-in) runs as part of starting the shell: text fed before VTE has attached
        // the terminal would be dropped.
        let inv = HostCommand.terminal(shell: HostCommand.defaultShell, in: directory, command: command, flatpak: Platform.isFlatpak)
        let env = inv.environment.map { "\($0.key)=\($0.value)" }
        withCStrings([inv.executable] + inv.arguments) { cArgv in
            withCStrings(env) { cEnv in
                vte_terminal_spawn_async(widget, 0, directory.path, cArgv, env.isEmpty ? nil : cEnv, 0, nil, nil, nil, -1, nil, nil, nil)
            }
        }
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

    private func withCStrings(_ strings: [String], _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Void) {
        var pointers: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) } + [nil]
        defer { pointers.forEach { free($0) } }
        pointers.withUnsafeMutableBufferPointer { body($0.baseAddress!) }
    }
}

/// Shows one VTE terminal widget, in a box so another tab's terminal can take its place.
struct VteView: AdwaitaWidget {
    let widget: UnsafeMutableRawPointer

    func container<Data>(data: WidgetData, type: Data.Type) -> ViewStorage where Data: ViewRenderData {
        let storage = ViewStorage(OpaquePointer(gtk_box_new(.GTK_ORIENTATION_VERTICAL, 0)))
        show(in: storage)
        return storage
    }

    func update<Data>(_ storage: ViewStorage, data: WidgetData, updateProperties: Bool, type: Data.Type) where Data: ViewRenderData {
        show(in: storage)
    }

    private func show(in storage: ViewStorage) {
        let box = UnsafeMutablePointer<GtkBox>(storage.opaquePointer)
        if let shown = storage.fields["vte-widget"] as? UnsafeMutableRawPointer {
            guard shown != widget else { return }
            gtk_box_remove(box, shown.assumingMemoryBound(to: GtkWidget.self))
        }
        let terminal = widget.assumingMemoryBound(to: GtkWidget.self)
        // A terminal shows in one place at a time: take it from a page that's still being torn down.
        if let parent = gtk_widget_get_parent(terminal) { gtk_box_remove(UnsafeMutablePointer<GtkBox>(OpaquePointer(parent)), terminal) }
        gtk_widget_set_hexpand(terminal, 1)
        gtk_widget_set_vexpand(terminal, 1)
        gtk_box_append(box, terminal)
        storage.fields["vte-widget"] = widget
    }
}

/// The Terminal tab: tabs for this project's folder and a new-tab button.
struct TerminalTab: View {
    let model: AppModel
    let directory: URL

    private var host: LinuxTerminalHost? { model.terminals as? LinuxTerminalHost }
    /// This folder's tabs only.
    private var tabs: [LinuxTerminalHost.Tab] { host?.tabs.filter { $0.directory == directory } ?? [] }
    private var selected: LinuxTerminalHost.Tab? { tabs.first { $0.id == host?.selectedID } ?? tabs.last }

    var view: Body {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(tabs) { tab in
                    Button(tab.directory.lastPathComponent) { host?.selectedID = tab.id; host?.onChange() }
                        .flat()
                }
                Button(icon: .default(icon: .listAdd)) { model.openTerminal(at: directory) }.flat().tooltip("New terminal tab")
                if let id = selected?.id {
                    Button(icon: .custom(name: "window-close-symbolic")) { host?.close(id) }.flat().tooltip("Close this tab")
                }
            }
            .halign(.start)
            if let tab = selected {
                VteView(widget: tab.widget).vexpand().hexpand().frame(minHeight: 420)
            } else {
                Button("Open a terminal here") { model.openTerminal(at: directory) }.pill().halign(.center).padding(24)
            }
        }
    }
}
