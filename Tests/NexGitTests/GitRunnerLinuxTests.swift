import Testing
import Foundation
@testable import NexGit
import NexTestSupport

@Suite(.timeLimit(.minutes(1))) struct GitRunnerLinuxTests {
    @Test func repoPathWithSpaces() async throws {
        let repo = TempRepo(name: "My Repo é")
        try "hello".write(to: repo.dir.appendingPathComponent("café notes.md"), atomically: true, encoding: .utf8)
        let status = try await repo.service.status(repo.dir)
        #expect(status.changes.map(\.path) == ["café notes.md"])
    }

    @Test func flatpakUsesHostGit() {
        let dir = URL(fileURLWithPath: "/home/alex/My Repo")
        let inv = GitRunner.invocation(["status"], in: dir, environment: ["GIT_TERMINAL_PROMPT": "0"], flatpak: true)
        #expect(inv.executable == "/usr/bin/flatpak-spawn")
        #expect(inv.arguments == ["--host", "--directory=/home/alex/My Repo", "--env=GIT_TERMINAL_PROMPT=0", "git", "status"])
    }

    @Test func outsideFlatpakGitComesFromPath() {
        let inv = GitRunner.invocation(["status"], in: URL(fileURLWithPath: "/tmp"), environment: [:], flatpak: false)
        #expect(inv.executable == "/usr/bin/env")
        #expect(inv.arguments == ["git", "status"])
    }

    /// Every one of many overlapping git calls must finish (Linux once lost end-of-output and waited for the timeout).
    @Test func manyConcurrentCallsAllFinish() async throws {
        let repo = TempRepo()
        let runner = GitRunner(extraEnvironment: repo.env)
        try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<40 { group.addTask { try await runner.run(["status", "--porcelain"], in: repo.dir, timeout: 10) } }
            for try await _ in group {}
        }
    }

    /// A streamed call (used for pull, push, clone) must return once git exits.
    @Test func streamReturnsWhenGitExits() async throws {
        let repo = TempRepo()
        for i in 0..<20 { repo.git("commit", "--allow-empty", "-m", "c\(i)") }
        let runner = GitRunner(extraEnvironment: repo.env)
        let box = Counter()
        let code = try await runner.stream(["log", "--oneline"], in: repo.dir) { _ in box.add() }
        #expect(code == 0)
        #expect(box.value == 20)
    }

    /// A child left behind by git (here a backgrounded `sleep`) keeps the output pipe open, so end-of-output
    /// never arrives; the call must still return soon after git itself exits, with what git printed.
    @Test func runReturnsWhenGitExitsWhileAChildHoldsThePipe() async throws {
        let repo = TempRepo()
        let runner = GitRunner(extraEnvironment: repo.env)
        let start = Date()
        let out = try await runner.run(["-c", "alias.hold=!echo hi; sleep 20 &", "hold"], in: repo.dir, timeout: 15)
        #expect(out.trimmingCharacters(in: .whitespacesAndNewlines) == "hi")
        #expect(Date().timeIntervalSince(start) < 5)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func add() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}
