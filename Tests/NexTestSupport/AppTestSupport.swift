import Foundation
import NexCore
import NexProcess
import NexGit
import NexApp

public final class FakeLogin: LoginItemControlling, @unchecked Sendable {
    public var isEnabled = false
    public init() {}
    public func setEnabled(_ on: Bool) throws { isEnabled = on }
}

public final class FakeNotifier: Notifying, @unchecked Sendable {
    public var status: NotificationAuthorization = .notDetermined
    public var grantOnRequest = true
    public private(set) var posted: [NotificationRequest] = []
    public init() {}
    public func authorizationStatus() async -> NotificationAuthorization { status }
    public func requestAuthorization() async -> Bool { status = grantOnRequest ? .authorized : .denied; return grantOnRequest }
    public func post(_ request: NotificationRequest) async { posted.append(request) }
}

/// Records what the model asked of the system.
@MainActor
public final class RecordingPlatformServices: PlatformServices {
    public private(set) var opened: [URL] = []
    public private(set) var revealed: [URL] = []
    public private(set) var copied: [String] = []
    public private(set) var openedWithApp: [(files: [URL], app: URL)] = []
    public private(set) var activations = 0
    public private(set) var widgetReloads = 0
    public private(set) var dockIconVisible: [Bool] = []
    /// Whether a main window exists to bring forward.
    public var hasWindow = false
    public var isAppActive = true

    public init() {}
    public func open(_ url: URL) { opened.append(url) }
    public func reveal(_ path: URL) { revealed.append(path) }
    public func copy(_ text: String) { copied.append(text) }
    public func open(_ files: [URL], withApplicationAt app: URL) { openedWithApp.append((files, app)) }
    @discardableResult public func activateMainWindow() -> Bool { activations += 1; return hasWindow }
    public func reloadWidgets() { widgetReloads += 1 }
    public func setDockIconVisible(_ visible: Bool) { dockIconVisible.append(visible) }
}

/// Records terminal tabs instead of starting shells.
@MainActor
public final class RecordingTerminalHost: TerminalHost {
    public struct Tab: Equatable { public let id: UUID; public let directory: URL; public let command: String? }
    public private(set) var tabs: [Tab] = []
    public var hasRunningPrograms = false
    public init() {}
    @discardableResult public func openTab(at directory: URL, command: String?) -> UUID {
        let tab = Tab(id: UUID(), directory: directory, command: command)
        tabs.append(tab)
        return tab.id
    }
    public func close(_ id: UUID) { tabs.removeAll { $0.id == id } }
    public func closeAll() { tabs.removeAll() }
}

/// A temporary projects folder and a model wired to it with fakes.
public final class Sandbox {
    public let notifier = FakeNotifier()
    public var appIsActive = false
    public let root: URL
    public init() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("nexui-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    public var scanRoot: URL { root.appendingPathComponent("Nexventures") }

    public func write(_ path: String, _ content: String = "") {
        let url = scanRoot.appendingPathComponent(path)
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! content.write(to: url, atomically: true, encoding: .utf8)
    }

    @MainActor
    public func makeModel(services: PlatformServices? = nil, terminals: TerminalHost? = nil, hostOS: HostOS = .current) -> AppModel {
        let settings = SettingsStore(fileURL: root.appendingPathComponent("settings.json"))
        settings.settings.scanRoot = scanRoot
        return AppModel(services: services ?? RecordingPlatformServices(),
                        terminals: terminals ?? RecordingTerminalHost(),
                        hostOS: hostOS,
                        settings: settings,
                        overrides: OverrideStore(fileURL: root.appendingPathComponent("overrides.json")),
                        processes: ProcessManager(killTimeout: 0.5),
                        git: GitService(),
                        login: FakeLogin(),
                        notifier: notifier,
                        appIsActive: { [weak self] in self?.appIsActive ?? true },
                        tasksFile: root.appendingPathComponent("tasks.json"),
                        snapshotDirectory: root.appendingPathComponent("shared"))
    }

    public static let vite = #"{"scripts":{"dev":"vite"},"devDependencies":{"vite":"5"},"dependencies":{"react":"18"}}"#
}
