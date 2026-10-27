import AppKit
import WidgetKit
import NexApp
import NexCore
import NexProcess
import NexGit
import NexTerminal

/// The Mac's side of `PlatformServices`: AppKit, WidgetKit and the Dock.
@MainActor
public final class MacPlatformServices: PlatformServices {
    public init() {}

    public func open(_ url: URL) { NSWorkspace.shared.open(url) }
    public func reveal(_ path: URL) { NSWorkspace.shared.activateFileViewerSelecting([path]) }

    public func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    public func open(_ files: [URL], withApplicationAt app: URL) {
        NSWorkspace.shared.open(files, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Restores a minimised window or fronts a visible one; false when every window was closed.
    @discardableResult
    public func activateMainWindow() -> Bool {
        let windows = NSApp?.windows ?? []
        defer { NSApp?.activate() }
        if let minimised = windows.first(where: { $0.isMiniaturized && $0.canBecomeMain }) {
            minimised.deminiaturize(nil)             // restore instead of opening a second window
            return true
        }
        return windows.contains { $0.isVisible && $0.canBecomeMain }
    }

    public func reloadWidgets() { WidgetCenter.shared.reloadAllTimelines() }

    public func setDockIconVisible(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
    }

    public var isAppActive: Bool { NSApp.isActive }
}

extension TerminalTabs: TerminalHost {
    public var hasRunningPrograms: Bool { anyForegroundProgram }

    @discardableResult
    public func openTab(at directory: URL, command: String?) -> UUID {
        let session = open(at: directory)
        if let command { session.send(command + "\n") }
        return session.id
    }
}

extension AppModel {
    /// The Mac app's model: AppKit services, SwiftTerm tabs, macOS notifications and login item.
    public convenience init(settings: SettingsStore? = nil,
                            overrides: OverrideStore? = nil,
                            processes: ProcessManager? = nil,
                            git: GitService = GitService(),
                            login: LoginItemControlling? = nil,
                            terminals: TerminalTabs? = nil,
                            notifier: Notifying? = nil,
                            appIsActive: (() -> Bool)? = nil,
                            devices: DevicesModel? = nil,
                            tasksFile: URL? = nil,
                            agents: AgentCatalog? = nil,
                            snapshotDirectory: URL? = nil) {
        self.init(services: MacPlatformServices(), terminals: terminals ?? TerminalTabs(),
                  settings: settings, overrides: overrides, processes: processes, git: git,
                  login: login ?? SMLoginItem(), notifier: notifier ?? SystemNotifier(), appIsActive: appIsActive,
                  devices: devices, tasksFile: tasksFile, agents: agents, snapshotDirectory: snapshotDirectory)
    }

    /// The SwiftTerm tabs behind `terminals` (always the case in the Mac app).
    public var terminalTabs: TerminalTabs? { terminals as? TerminalTabs }
}
