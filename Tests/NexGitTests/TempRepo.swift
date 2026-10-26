import Foundation
@testable import NexGit

/// Real git repositories in temp dirs. A throwaway GIT_CONFIG_GLOBAL keeps tests off ~/.gitconfig.
final class TempRepo {
    let base: URL
    let dir: URL
    let globalConfig: URL

    var env: [String: String] {
        ["GIT_CONFIG_GLOBAL": globalConfig.path, "GIT_CONFIG_NOSYSTEM": "1",
         "GIT_AUTHOR_DATE": "2026-01-01T00:00:00Z", "GIT_COMMITTER_DATE": "2026-01-01T00:00:00Z"]
    }

    var service: GitService { GitService(runner: GitRunner(extraEnvironment: env)) }

    init(name: String = "repo", initialize: Bool = true, identity: Bool = true) {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("nexgit-\(UUID().uuidString)")
        dir = base.appendingPathComponent(name)
        globalConfig = base.appendingPathComponent("gitconfig")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: globalConfig.path, contents: nil)
        if initialize {
            git("init", "-b", "main")
            if identity { configureIdentity() }
        }
    }

    deinit { try? FileManager.default.removeItem(at: base) }

    func configureIdentity(name: String = "Test User", email: String = "test@example.com") {
        git("config", "user.name", name)
        git("config", "user.email", email)
        git("config", "commit.gpgsign", "false")
    }

    @discardableResult
    func git(_ args: String..., in cwd: URL? = nil) -> String { run(args, in: cwd ?? dir) }

    @discardableResult
    func run(_ args: [String], in cwd: URL) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = args
        p.currentDirectoryURL = cwd
        p.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        try! p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    func write(_ path: String, _ content: String, in cwd: URL? = nil) {
        let url = (cwd ?? dir).appendingPathComponent(path)
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! content.write(to: url, atomically: true, encoding: .utf8)
    }

    func commitAll(_ message: String = "commit", in cwd: URL? = nil) {
        run(["add", "-A"], in: cwd ?? dir)
        run(["commit", "-m", message], in: cwd ?? dir)
    }

    /// Creates a bare repo, wires it as origin and pushes main.
    @discardableResult
    func attachBareRemote() -> URL {
        let bare = base.appendingPathComponent("remote.git")
        try! FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        run(["init", "--bare", "-b", "main"], in: bare)
        git("remote", "add", "origin", bare.path)
        return bare
    }

    /// A second working copy of the remote, with identity set, for simulating a collaborator.
    func collaboratorClone(of bare: URL) -> URL {
        let clone = base.appendingPathComponent("collab")
        run(["clone", bare.path, "collab"], in: base)
        run(["config", "user.name", "Collab"], in: clone)
        run(["config", "user.email", "collab@example.com"], in: clone)
        run(["config", "commit.gpgsign", "false"], in: clone)
        return clone
    }
}
