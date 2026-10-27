import Foundation
import NexCore
import Observation
import NexGit

/// State and actions for one repository, in the style of GitHub Desktop.
@MainActor @Observable
public final class GitModel {
    public let repo: URL
    private let service: GitService

    public private(set) var status: RepoStatus?
    public private(set) var branches: [String] = []
    public private(set) var history: [CommitInfo] = []
    public private(set) var identity = GitIdentity(name: nil, email: nil)
    public private(set) var selectedFile: FileChange?
    public private(set) var diffText = ""
    public private(set) var isBusy = false
    public private(set) var pendingPullChoice = false
    public var errorMessage: String?
    public var summary = ""
    public var descriptionText = ""

    public init(repo: URL, service: GitService) {
        self.repo = repo
        self.service = service
    }

    public var needsIdentity: Bool { identity.name == nil || identity.email == nil }
    public var stagedCount: Int { status?.changes.filter(\.isStaged).count ?? 0 }

    // MARK: - Loading

    public func reload() async {
        do {
            let s = try await service.status(repo)
            status = s
            branches = (try? await service.branches(repo)) ?? []
            history = (try? await service.log(repo, limit: 30)) ?? []
            identity = (try? await service.effectiveIdentity(repo)) ?? GitIdentity(name: nil, email: nil)
            if let selected = selectedFile, !s.changes.contains(where: { $0.path == selected.path }) {
                selectedFile = nil
                diffText = ""
            }
        } catch {
            status = nil
            errorMessage = describe(error)
        }
    }

    public func select(_ file: FileChange) async {
        selectedFile = file
        diffText = (try? await service.diff(repo, file: file)) ?? ""
    }

    // MARK: - Actions

    public func toggleStage(_ file: FileChange) async {
        await perform {
            if file.isStaged {
                try await service.unstage(repo, paths: [file.path])
            } else {
                try await service.stage(repo, paths: [file.path])
            }
        }
    }

    public func stageAll(_ on: Bool) async {
        guard let changes = status?.changes else { return }
        await perform {
            let paths = changes.filter { on ? !$0.isStaged : $0.isStaged }.map(\.path)
            if on { try await service.stage(repo, paths: paths) } else { try await service.unstage(repo, paths: paths) }
        }
    }

    public func discard(_ file: FileChange) async {
        await perform { try await service.discard(repo, paths: [file.path]) }
    }

    /// Commits the staged files; if nothing is staged, everything is committed (like GitHub Desktop's default).
    public func commit() async {
        guard !summary.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = GitError.emptyMessage.errorDescription
            return
        }
        await perform {
            if stagedCount == 0, let all = status?.changes.map(\.path), !all.isEmpty {
                try await service.stage(repo, paths: all)
            }
            try await service.commit(repo, summary: summary, description: descriptionText)
            summary = ""
            descriptionText = ""
        }
    }

    public func fetch() async { await perform { try await service.fetch(repo) } }

    public func pull(strategy: PullStrategy) async {
        await perform {
            do {
                try await service.pull(repo, strategy: strategy)
                pendingPullChoice = false
            } catch GitError.cannotFastForward {
                pendingPullChoice = true
                throw GitError.cannotFastForward
            }
        }
    }

    public func dismissPullChoice() { pendingPullChoice = false; errorMessage = nil }

    public func push() async { await perform { try await service.push(repo) } }

    public func switchBranch(_ name: String) async { await perform { try await service.switchBranch(repo, to: name) } }
    public func createBranch(_ name: String) async { await perform { try await service.createBranch(repo, named: name) } }

    public func saveIdentity(_ id: GitIdentity, scope: GitScope) async {
        await perform { try await service.setIdentity(id, repo: repo, scope: scope) }
    }

    // MARK: - Plumbing

    private func perform(_ body: () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        do { try await body() } catch { errorMessage = describe(error) }
        await reload()
        if let selected = selectedFile, let fresh = status?.changes.first(where: { $0.path == selected.path }) {
            diffText = (try? await service.diff(repo, file: fresh)) ?? ""
        }
        isBusy = false
    }

    private func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
