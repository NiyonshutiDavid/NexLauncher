import Testing
import Foundation
@testable import NexGit
import NexTestSupport

@Suite struct GitServiceWriteTests {
    private func seeded() -> (TempRepo, URL) {
        let r = TempRepo()
        r.write("a.txt", "a\n"); r.commitAll("init")
        let bare = r.attachBareRemote()
        r.git("push", "-u", "origin", "main")
        return (r, bare)
    }

    @Test func stageThenCommitCreatesCommit() async throws {
        let r = TempRepo()
        r.write("a.txt", "a")
        let svc = r.service
        try await svc.stage(r.dir, paths: ["a.txt"])
        try await svc.commit(r.dir, summary: "add a", description: "")
        #expect(try await svc.log(r.dir, limit: 5).map(\.subject) == ["add a"])
        #expect(try await svc.status(r.dir).changes.isEmpty)
    }

    @Test func commitWithEmptySummaryThrowsEmptyMessage() async throws {
        let r = TempRepo()
        r.write("a.txt", "a")
        try await r.service.stage(r.dir, paths: ["a.txt"])
        await #expect(throws: GitError.emptyMessage) { try await r.service.commit(r.dir, summary: "   ", description: "") }
        #expect(try await r.service.status(r.dir).changes.first?.isStaged == true)
    }

    @Test func commitWithNothingStagedThrowsNothingToCommit() async throws {
        let r = TempRepo()
        r.write("a.txt", "a"); r.commitAll()
        r.write("a.txt", "b")
        await #expect(throws: GitError.nothingToCommit) { try await r.service.commit(r.dir, summary: "x", description: "") }
    }

    @Test func commitIncludesDescriptionBody() async throws {
        let r = TempRepo()
        r.write("a.txt", "a")
        try await r.service.stage(r.dir, paths: ["a.txt"])
        try await r.service.commit(r.dir, summary: "subject", description: "the body")
        #expect(r.git("log", "-1", "--format=%B").contains("the body"))
    }

    @Test func unstageRestoresIndex() async throws {
        let r = TempRepo()
        r.write("a.txt", "a"); r.commitAll()
        r.write("a.txt", "b")
        try await r.service.stage(r.dir, paths: ["a.txt"])
        try await r.service.unstage(r.dir, paths: ["a.txt"])
        let c = try await r.service.status(r.dir).changes[0]
        #expect(!c.isStaged)
    }

    @Test func unstageWorksBeforeFirstCommit() async throws {
        let r = TempRepo()
        r.write("a.txt", "a")
        try await r.service.stage(r.dir, paths: ["a.txt"])
        try await r.service.unstage(r.dir, paths: ["a.txt"])
        #expect(try await r.service.status(r.dir).changes.first?.isUntracked == true)
    }

    @Test func discardRevertsTrackedAndDeletesUntrackedOnlyWhenListed() async throws {
        let r = TempRepo()
        r.write("a.txt", "orig"); r.commitAll()
        r.write("a.txt", "dirty"); r.write("keep.txt", "keep"); r.write("drop.txt", "drop")
        try await r.service.discard(r.dir, paths: ["a.txt", "drop.txt"])
        #expect(try String(contentsOf: r.dir.appendingPathComponent("a.txt"), encoding: .utf8) == "orig")
        #expect(!FileManager.default.fileExists(atPath: r.dir.appendingPathComponent("drop.txt").path))
        #expect(FileManager.default.fileExists(atPath: r.dir.appendingPathComponent("keep.txt").path))
    }

    @Test func pushSetsUpstreamWhenMissing() async throws {
        let r = TempRepo()
        r.write("a.txt", "a"); r.commitAll()
        r.attachBareRemote()
        try await r.service.push(r.dir)
        #expect(try await r.service.status(r.dir).upstream == "origin/main")
    }

    @Test func pushNeverForces() async throws {
        let (r, bare) = seeded()
        let collab = r.collaboratorClone(of: bare)
        r.write("c.txt", "c", in: collab); r.commitAll("remote work", in: collab); r.run(["push"], in: collab)
        r.write("b.txt", "b"); r.commitAll("local work")
        await #expect(throws: GitError.self) { try await r.service.push(r.dir) }
        #expect(r.run(["log", "--format=%s"], in: bare).contains("remote work"))
        #expect(!r.run(["log", "--format=%s"], in: bare).contains("local work"))
    }

    @Test func pushWithoutRemoteThrows() async throws {
        let r = TempRepo()
        r.write("a.txt", "a"); r.commitAll()
        await #expect(throws: GitError.self) { try await r.service.push(r.dir) }
    }

    @Test func pullFastForwards() async throws {
        let (r, bare) = seeded()
        let collab = r.collaboratorClone(of: bare)
        r.write("c.txt", "c", in: collab); r.commitAll("remote", in: collab); r.run(["push"], in: collab)
        try await r.service.pull(r.dir, strategy: .ffOnly)
        #expect(FileManager.default.fileExists(atPath: r.dir.appendingPathComponent("c.txt").path))
    }

    @Test func pullNonFastForwardThrowsCannotFastForwardAndLeavesTreeClean() async throws {
        let (r, bare) = seeded()
        let collab = r.collaboratorClone(of: bare)
        r.write("c.txt", "c", in: collab); r.commitAll("remote", in: collab); r.run(["push"], in: collab)
        r.write("b.txt", "b"); r.commitAll("local")
        await #expect(throws: GitError.cannotFastForward) { try await r.service.pull(r.dir, strategy: .ffOnly) }
        #expect(try await r.service.status(r.dir).changes.isEmpty)
    }

    @Test func pullMergeConflictThrowsConflictsWithFileList() async throws {
        let (r, bare) = seeded()
        let collab = r.collaboratorClone(of: bare)
        r.write("a.txt", "remote\n", in: collab); r.commitAll("remote", in: collab); r.run(["push"], in: collab)
        r.write("a.txt", "local\n"); r.commitAll("local")
        await #expect(throws: GitError.conflicts(["a.txt"])) { try await r.service.pull(r.dir, strategy: .merge) }
    }

    @Test func pullWithNoUpstreamThrowsNoUpstream() async throws {
        let r = TempRepo()
        r.write("a.txt", "a"); r.commitAll()
        await #expect(throws: GitError.noUpstream) { try await r.service.pull(r.dir, strategy: .ffOnly) }
    }

    @Test func fetchUpdatesBehindCount() async throws {
        let (r, bare) = seeded()
        let collab = r.collaboratorClone(of: bare)
        r.write("c.txt", "c", in: collab); r.commitAll("remote", in: collab); r.run(["push"], in: collab)
        try await r.service.fetch(r.dir)
        #expect(try await r.service.status(r.dir).behind == 1)
    }

    @Test func switchAndCreateBranch() async throws {
        let r = TempRepo()
        r.write("a.txt", "a"); r.commitAll()
        try await r.service.createBranch(r.dir, named: "feature")
        #expect(try await r.service.status(r.dir).branch == "feature")
        try await r.service.switchBranch(r.dir, to: "main")
        #expect(try await r.service.status(r.dir).branch == "main")
    }

    @Test func authFailureMappedToAuthFailed() {
        #expect(GitService.classify("remote: Invalid username or password.\nfatal: Authentication failed for 'https://x/y.git/'") == .authFailed("fatal: Authentication failed for 'https://x/y.git/'"))
        if case .authFailed = GitService.classify("git@github.com: Permission denied (publickey).") {} else { Issue.record("publickey not mapped") }
        if case .authFailed = GitService.classify("fatal: could not read Username for 'https://github.com': terminal prompts disabled") {} else { Issue.record("username prompt not mapped") }
    }
}
