import Testing
import Foundation
import NexCore
@testable import NexProcess

/// Runs only on Linux (GitHub Actions); the same behaviour on macOS is covered by ProcessManagerTests.
@Suite(.enabled(if: HostOS.current == .linux), .serialized)
struct ProcessManagerLinuxTests {
    private func run(_ command: String, in dir: URL, environment: [String: String] = [:]) async throws -> (output: [String], code: Int32) {
        let (pid, fd) = try ProcessSpawner.spawn(command: command, directory: dir, environment: environment)
        return await withCheckedContinuation { cont in
            let box = LinesBox()
            ProcessSpawner.pump(fd: fd, pid: pid, onLines: { box.add($0) }, onExit: { code in cont.resume(returning: (box.lines, code)) })
        }
    }

    private func tempDir(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)/\(name)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func spawnRunsInDirectory() async throws {
        let dir = try tempDir("Café App")
        let result = try await run("pwd", in: dir)
        #expect(result.output.last == dir.path)
        #expect(result.code == 0)
    }

    @Test func stopKillsWholeGroup() async throws {
        let (pid, fd) = try ProcessSpawner.spawn(command: "sleep 300 & sleep 300; wait", directory: try tempDir("group"))
        ProcessSpawner.pump(fd: fd, pid: pid, onLines: { _ in }, onExit: { _ in })
        try await Task.sleep(for: .milliseconds(300))
        #expect(!processesInGroup(pid).isEmpty)
        await ProcessSpawner.terminateGroup(pid, grace: 2)
        try await Task.sleep(for: .milliseconds(300))
        #expect(processesInGroup(pid).isEmpty)
    }

    @Test func loginShellLoadsProfile() async throws {
        let home = try tempDir("home")
        let tools = home.appendingPathComponent("tools")
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        let tool = tools.appendingPathComponent("nex-test-tool")
        try "#!/bin/sh\necho ok\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        try #"export PATH="$HOME/tools:$PATH""#.write(to: home.appendingPathComponent(".bash_profile"), atomically: true, encoding: .utf8)
        try #"export PATH="$HOME/tools:$PATH""#.write(to: home.appendingPathComponent(".profile"), atomically: true, encoding: .utf8)
        let result = try await run("command -v nex-test-tool", in: home, environment: ["HOME": home.path])
        #expect(result.output.last == tool.path)
    }

    /// Process ids whose process group (field 5 of /proc/<pid>/stat) is `pgid`.
    private func processesInGroup(_ pgid: pid_t) -> [Int] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: "/proc")) ?? []
        return entries.compactMap { Int($0) }.filter { p in
            guard let stat = try? String(contentsOfFile: "/proc/\(p)/stat", encoding: .utf8),
                  let close = stat.lastIndex(of: ")") else { return false }
            let fields = stat[stat.index(after: close)...].split(separator: " ")
            return fields.count > 2 && Int(fields[2]) == Int(pgid) && !stat.contains(") Z ")
        }
    }
}

private final class LinesBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    func add(_ lines: [String]) { lock.lock(); storage += lines; lock.unlock() }
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return storage }
}
