import Foundation

public enum GitError: Error, Equatable, Sendable {
    case notARepo
    case commandFailed(code: Int32, stderr: String)
    case timeout
    case noUpstream
    case nothingToCommit
    case emptyMessage
    case cannotFastForward
    case conflicts([String])
    case authFailed(String)
}

extension GitError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notARepo: return "This folder is not a git repository."
        case .commandFailed(let code, let stderr): return stderr.isEmpty ? "git failed (exit \(code))." : stderr
        case .timeout: return "git took too long and was stopped."
        case .noUpstream: return "This branch has no upstream branch yet."
        case .nothingToCommit: return "There are no staged changes to commit."
        case .emptyMessage: return "Enter a commit summary first."
        case .cannotFastForward: return "Can't fast-forward: your branch and the remote have diverged."
        case .conflicts(let files): return "Merge conflicts in: " + files.joined(separator: ", ")
        case .authFailed(let detail): return "Authentication failed. \(detail)"
        }
    }
}

public struct FileChange: Hashable, Sendable, Identifiable {
    public let path: String
    public let index: Character
    public let worktree: Character
    public var id: String { path }
    public var isUntracked: Bool { index == "?" }
    public var isStaged: Bool { index != "." && index != "?" && index != " " }

    public init(path: String, index: Character, worktree: Character) {
        self.path = path
        self.index = index
        self.worktree = worktree
    }
}

public struct RepoStatus: Sendable, Equatable {
    public let branch: String?
    public let upstream: String?
    public let ahead: Int
    public let behind: Int
    public let changes: [FileChange]
    public let isDetached: Bool
    public let hasCommits: Bool
}

public struct CommitInfo: Identifiable, Sendable, Equatable {
    public let id: String
    public let subject: String
    public let author: String
    public let date: Date
}

public struct GitIdentity: Equatable, Sendable {
    public var name: String?
    public var email: String?
    public init(name: String?, email: String?) {
        self.name = name
        self.email = email
    }
}

public enum GitScope: Sendable { case global, repo }
public enum PullStrategy: Sendable { case ffOnly, merge, rebase }
