import Testing
import Foundation
@testable import NexGit
import NexTestSupport

@Suite struct GitRunnerLinuxTests {
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
}
