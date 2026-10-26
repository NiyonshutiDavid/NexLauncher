import Foundation

/// Builds throwaway directory trees for tests.
final class TempTree {
    let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nex-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func write(_ path: String, _ content: String = "") -> URL {
        let url = root.appendingPathComponent(path)
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func mkdir(_ path: String) {
        try! FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
    }

    func symlink(_ path: String, to dest: String) {
        let link = root.appendingPathComponent(path)
        try! FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: root.appendingPathComponent(dest).path)
    }

    static let viteApp = #"{"scripts":{"dev":"vite"},"devDependencies":{"vite":"^5.0.0"},"dependencies":{"react":"^18.0.0"}}"#
}
