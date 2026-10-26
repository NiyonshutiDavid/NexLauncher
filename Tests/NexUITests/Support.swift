import Foundation
import NexCore
import NexProcess
import NexGit
import NexTerminal
@testable import NexUI

final class FakeLogin: LoginItemControlling, @unchecked Sendable {
    var isEnabled = false
    func setEnabled(_ on: Bool) throws { isEnabled = on }
}

final class FakeNotifier: Notifying, @unchecked Sendable {
    var status: NotificationAuthorization = .notDetermined
    var grantOnRequest = true
    private(set) var posted: [NotificationRequest] = []
    func authorizationStatus() async -> NotificationAuthorization { status }
    func requestAuthorization() async -> Bool { status = grantOnRequest ? .authorized : .denied; return grantOnRequest }
    func post(_ request: NotificationRequest) async { posted.append(request) }
}

final class Sandbox {
    let notifier = FakeNotifier()
    var appIsActive = false
    let root: URL
    init() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("nexui-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    var scanRoot: URL { root.appendingPathComponent("Nexventures") }

    func write(_ path: String, _ content: String = "") {
        let url = scanRoot.appendingPathComponent(path)
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! content.write(to: url, atomically: true, encoding: .utf8)
    }

    @MainActor
    func makeModel() -> AppModel {
        let settings = SettingsStore(fileURL: root.appendingPathComponent("settings.json"))
        settings.settings.scanRoot = scanRoot
        return AppModel(settings: settings,
                        overrides: OverrideStore(fileURL: root.appendingPathComponent("overrides.json")),
                        processes: ProcessManager(killTimeout: 0.5),
                        git: GitService(),
                        login: FakeLogin(),
                        notifier: notifier,
                        appIsActive: { [unowned self] in self.appIsActive },
                        tasksFile: root.appendingPathComponent("tasks.json"),
                        snapshotDirectory: root.appendingPathComponent("shared"))
    }

    static let vite = #"{"scripts":{"dev":"vite"},"devDependencies":{"vite":"5"},"dependencies":{"react":"18"}}"#
}
