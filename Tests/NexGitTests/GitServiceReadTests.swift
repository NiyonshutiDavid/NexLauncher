import Testing
import Foundation
@testable import NexGit

@Suite struct GitServiceReadTests {
    @Test func statusCleanRepo() async throws {
        let r = TempRepo()
        r.write("a.txt", "a"); r.commitAll()
        let s = try await r.service.status(r.dir)
        #expect(s.branch == "main")
        #expect(s.changes.isEmpty)
        #expect(s.hasCommits)
        #expect(!s.isDetached)
    }

    @Test func statusShowsUntrackedAndModified() async throws {
        let r = TempRepo()
        r.write("a.txt", "a"); r.commitAll()
        r.write("a.txt", "changed"); r.write("new.txt", "n")
        let s = try await r.service.status(r.dir)
        #expect(s.changes.count == 2)
        #expect(s.changes.first { $0.path == "new.txt" }?.isUntracked == true)
        #expect(s.changes.first { $0.path == "a.txt" }?.isStaged == false)
    }

    @Test func statusStagedVsUnstaged() async throws {
        let r = TempRepo()
        r.write("a.txt", "a"); r.write("b.txt", "b"); r.commitAll()
        r.write("a.txt", "A2"); r.write("b.txt", "B2")
        r.git("add", "a.txt")
        let s = try await r.service.status(r.dir)
        #expect(s.changes.first { $0.path == "a.txt" }?.isStaged == true)
        #expect(s.changes.first { $0.path == "b.txt" }?.isStaged == false)
    }

    @Test func statusInEmptyRepoHasNoCommits() async throws {
        let r = TempRepo()
        r.write("a.txt", "a")
        let s = try await r.service.status(r.dir)
        #expect(!s.hasCommits)
        #expect(s.branch == "main")
        #expect(s.changes.count == 1)
    }

    @Test func statusDetachedHead() async throws {
        let r = TempRepo()
        r.write("a.txt", "a"); r.commitAll()
        r.git("checkout", "--detach")
        let s = try await r.service.status(r.dir)
        #expect(s.isDetached)
        #expect(s.branch == nil)
    }

    @Test func statusWithoutUpstreamHasNilUpstream() async throws {
        let r = TempRepo()
        r.write("a.txt", "a"); r.commitAll()
        let s = try await r.service.status(r.dir)
        #expect(s.upstream == nil)
        #expect(s.ahead == 0 && s.behind == 0)
    }

    @Test func statusAheadBehindAgainstBareRemote() async throws {
        let r = TempRepo()
        r.write("a.txt", "a"); r.commitAll("one")
        let bare = r.attachBareRemote()
        r.git("push", "-u", "origin", "main")
        let collab = r.collaboratorClone(of: bare)
        r.write("c.txt", "c", in: collab); r.commitAll("remote", in: collab)
        r.run(["push"], in: collab)
        r.write("b.txt", "b"); r.commitAll("local")
        r.git("fetch")
        let s = try await r.service.status(r.dir)
        #expect(s.upstream == "origin/main")
        #expect(s.ahead == 1)
        #expect(s.behind == 1)
    }

    @Test func notARepoThrows() async {
        let r = TempRepo(initialize: false)
        await #expect(throws: GitError.notARepo) { _ = try await r.service.status(r.dir) }
    }

    @Test func pathWithSpaces() async throws {
        let r = TempRepo(name: "My Project", identity: true)
        r.write("my file.txt", "x")
        let s = try await r.service.status(r.dir)
        #expect(s.changes.first?.path == "my file.txt")
    }

    @Test func diffReturnsUnifiedDiff() async throws {
        let r = TempRepo()
        r.write("a.txt", "one\n"); r.commitAll()
        r.write("a.txt", "two\n")
        let change = try await r.service.status(r.dir).changes[0]
        let diff = try await r.service.diff(r.dir, file: change)
        #expect(diff.contains("-one"))
        #expect(diff.contains("+two"))
    }

    @Test func diffOfUntrackedFileShowsContent() async throws {
        let r = TempRepo()
        r.write("n.txt", "fresh\n")
        let change = try await r.service.status(r.dir).changes[0]
        #expect(try await r.service.diff(r.dir, file: change).contains("+fresh"))
    }

    @Test func logReturnsNewestFirst() async throws {
        let r = TempRepo()
        r.write("a.txt", "1"); r.commitAll("first")
        r.write("a.txt", "2"); r.commitAll("second")
        let log = try await r.service.log(r.dir, limit: 10)
        #expect(log.map(\.subject) == ["second", "first"])
        #expect(log[0].author == "Test User")
    }

    @Test func logOfEmptyRepoIsEmpty() async throws {
        let r = TempRepo()
        #expect(try await r.service.log(r.dir, limit: 5).isEmpty)
    }

    @Test func branchesListsLocal() async throws {
        let r = TempRepo()
        r.write("a.txt", "a"); r.commitAll()
        r.git("branch", "feature")
        #expect(Set(try await r.service.branches(r.dir)) == ["main", "feature"])
    }

    @Test func setAndReadRepoIdentity() async throws {
        let r = TempRepo(identity: false)
        let svc = r.service
        #expect(try await svc.identity(r.dir, scope: .repo) == GitIdentity(name: nil, email: nil))
        try await svc.setIdentity(GitIdentity(name: "David", email: "d@x.com"), repo: r.dir, scope: .repo)
        #expect(try await svc.identity(r.dir, scope: .repo) == GitIdentity(name: "David", email: "d@x.com"))
    }

    @Test func setGlobalIdentityWritesGlobalConfigOnly() async throws {
        let r = TempRepo(identity: false)
        let svc = r.service
        try await svc.setIdentity(GitIdentity(name: "G", email: "g@x.com"), repo: r.dir, scope: .global)
        #expect(try await svc.identity(r.dir, scope: .global).name == "G")
        #expect(try await svc.identity(r.dir, scope: .repo).name == nil)
        #expect(try await svc.effectiveIdentity(r.dir).email == "g@x.com")
    }

    @Test func findReposFindsNestedRepos() throws {
        let r = TempRepo(name: "project", initialize: false)
        for sub in ["frontend", "backend"] {
            let d = r.dir.appendingPathComponent(sub)
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            r.run(["init", "-b", "main"], in: d)
        }
        try FileManager.default.createDirectory(at: r.dir.appendingPathComponent("node_modules/x/.git"), withIntermediateDirectories: true)
        let found = r.service.findRepos(under: r.dir).map(\.lastPathComponent)
        #expect(found == ["backend", "frontend"])
    }

    @Test func findReposIncludesRootRepo() {
        let r = TempRepo()
        #expect(r.service.findRepos(under: r.dir).map(\.lastPathComponent) == ["repo"])
    }
}
