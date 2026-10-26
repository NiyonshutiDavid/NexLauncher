import Testing
import Foundation
@testable import NexGit
import NexTestSupport

private final class Lines: @unchecked Sendable {
    private let lock = NSLock(); private var items: [String] = []
    func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}

@Suite struct ProjectCreatorTests {
    private func parent() -> (TempRepo, URL) {
        let r = TempRepo(name: "parent", initialize: false)
        return (r, r.dir)
    }
    private func creator(_ r: TempRepo, extra: [String: String] = [:]) -> ProjectCreator {
        ProjectCreator(git: GitService(runner: GitRunner(extraEnvironment: r.env.merging(extra) { $1 })))
    }
    /// A bare repo with one commit, returned as a path usable as a clone URL.
    private func sourceRepo() -> (TempRepo, URL) {
        let r = TempRepo()
        r.write("hello.txt", "hi"); r.write("sub dir/x.txt", "x"); r.commitAll("first")
        let bare = r.attachBareRemote()
        r.git("push", "-u", "origin", "main")
        return (r, bare)
    }

    @Test func validateRejectsEmptyDotDotSlashAndExisting() {
        let (r, p) = parent()
        r.write("taken/x", "x", in: p)
        #expect(ProjectCreator.validate(name: "", in: p) == .empty)
        #expect(ProjectCreator.validate(name: "   ", in: p) == .empty)
        #expect(ProjectCreator.validate(name: "..", in: p) == .invalidCharacters)
        #expect(ProjectCreator.validate(name: ".", in: p) == .invalidCharacters)
        #expect(ProjectCreator.validate(name: "a/b", in: p) == .invalidCharacters)
        #expect(ProjectCreator.validate(name: "../x", in: p) == .invalidCharacters)
        #expect(ProjectCreator.validate(name: "taken", in: p) == .alreadyExists)
    }

    @Test func validateAcceptsSpacesAndUnicode() {
        let (pr, p) = parent()
        defer { _ = pr }
        #expect(ProjectCreator.validate(name: "My App é", in: p) == nil)
    }

    @Test func repositoryNameFromHTTPSAndSSH() {
        #expect(ProjectCreator.repositoryName(from: "https://github.com/x/y.git") == "y")
        #expect(ProjectCreator.repositoryName(from: "git@github.com:x/y.git") == "y")
        #expect(ProjectCreator.repositoryName(from: "https://h/x/y/") == "y")
        #expect(ProjectCreator.repositoryName(from: "https://h/x/y") == "y")
        #expect(ProjectCreator.repositoryName(from: "  ") == "")
    }

    @Test func createFolderMakesDirectoryAndInitialisesGitWithBranch() async throws {
        let (r, p) = parent()
        let url = try await creator(r).createFolder(name: "New App", in: p, initGit: true, defaultBranch: "trunk")
        #expect(url.lastPathComponent == "New App")
        #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path))
        #expect(r.run(["symbolic-ref", "--short", "HEAD"], in: url).trimmingCharacters(in: .whitespacesAndNewlines) == "trunk")
    }

    @Test func createFolderWithoutGit() async throws {
        let (r, p) = parent()
        let url = try await creator(r).createFolder(name: "plain", in: p, initGit: false, defaultBranch: "main")
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(!FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path))
    }

    @Test func createFolderRejectsInvalidName() async {
        let (r, p) = parent()
        await #expect(throws: ProjectCreationError.invalidName(.invalidCharacters)) {
            _ = try await creator(r).createFolder(name: "a/b", in: p, initGit: false, defaultBranch: "main")
        }
    }

    @Test func createFolderRejectsDashBranch() async {
        let (r, p) = parent()
        await #expect(throws: ProjectCreationError.invalidBranch) {
            _ = try await creator(r).createFolder(name: "ok", in: p, initGit: true, defaultBranch: "--bad")
        }
    }

    @Test func cloneFromLocalBareRepoCopiesFilesAndReportsProgress() async throws {
        let (src, bare) = sourceRepo()
        let (pr, p) = parent()
        defer { _ = pr }
        let lines = Lines()
        let url = try await creator(src).clone(url: bare.path, name: "copy", in: p, onLine: { lines.add($0) })
        #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("hello.txt").path))
        #expect(lines.all.contains { $0.contains("Cloning into") })
    }

    @Test func cloneIntoNameWithSpaces() async throws {
        let (src, bare) = sourceRepo()
        let (pr, p) = parent()
        defer { _ = pr }
        let url = try await creator(src).clone(url: bare.path, name: "My Clone", in: p, onLine: { _ in })
        #expect(url.lastPathComponent == "My Clone")
        #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("sub dir/x.txt").path))
    }

    @Test func urlStartingWithDashIsNotAnOption() async {
        let (r, p) = parent()
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("nex-marker-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: marker) }
        await #expect(throws: ProjectCreationError.invalidURL) {
            _ = try await creator(r).clone(url: "--upload-pack=touch \(marker.path)", name: "x", in: p, onLine: { _ in })
        }
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(!FileManager.default.fileExists(atPath: p.appendingPathComponent("x").path))
    }

    @Test func extTransportIsRejected() async {
        let (r, p) = parent()
        await #expect(throws: ProjectCreationError.invalidURL) {
            _ = try await creator(r).clone(url: "ext::sh -c touch% /tmp/nex-ext", name: "x", in: p, onLine: { _ in })
        }
    }

    @Test func failedCloneLeavesNoPartialFolder() async {
        let (r, p) = parent()
        await #expect(throws: ProjectCreationError.self) {
            _ = try await creator(r).clone(url: "/nonexistent/repo-\(UUID().uuidString).git", name: "gone", in: p, onLine: { _ in })
        }
        #expect(!FileManager.default.fileExists(atPath: p.appendingPathComponent("gone").path))
    }

    @Test func cancelledCloneLeavesNoPartialFolder() async throws {
        let (r, p) = parent()
        let lines = Lines()
        let slow = creator(r, extra: ["GIT_SSH_COMMAND": "sleep 30 #"])      // ssh "connects" by sleeping
        let task = Task { try await slow.clone(url: "ssh://example.invalid/x.git", name: "slow", in: p, onLine: { lines.add($0) }) }
        let deadline = Date().addingTimeInterval(10)
        while lines.all.isEmpty && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        task.cancel()
        let result = await task.result
        #expect(throws: (any Error).self) { try result.get() }
        #expect(!FileManager.default.fileExists(atPath: p.appendingPathComponent("slow").path))
    }

    @Test func authFailureIsMapped() {
        if case .authFailed = GitService.classify("fatal: Authentication failed for 'https://x/y.git/'") {} else { Issue.record("not mapped") }
    }
}

@Suite struct PartialCleanupTests {
    @Test func doesNotRemoveAFolderThatAlreadyExisted() {
        let existing = GitError.commandFailed(code: 128, stderr: "fatal: destination path 'x' already exists and is not an empty directory.")
        #expect(!ProjectCreator.shouldRemovePartial(after: existing))
    }
    @Test func removesPartialFolderForOtherFailures() {
        #expect(ProjectCreator.shouldRemovePartial(after: GitError.commandFailed(code: 128, stderr: "fatal: could not read from remote repository")))
        #expect(ProjectCreator.shouldRemovePartial(after: GitError.authFailed("nope")))
        #expect(ProjectCreator.shouldRemovePartial(after: CancellationError()))
    }
}
