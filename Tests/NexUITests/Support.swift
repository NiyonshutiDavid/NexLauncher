import Foundation
import NexCore
import NexProcess
import NexGit
@testable import NexUI

final class Sandbox {
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
                        snapshotDirectory: root.appendingPathComponent("shared"))
    }

    static let vite = #"{"scripts":{"dev":"vite"},"devDependencies":{"vite":"5"},"dependencies":{"react":"18"}}"#
}
