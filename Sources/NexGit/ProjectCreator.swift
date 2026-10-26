import Foundation

public enum NameError: Error, Equatable, Sendable { case empty, invalidCharacters, alreadyExists }

public enum ProjectCreationError: Error, Equatable, Sendable {
    case invalidName(NameError)
    case invalidURL
    case invalidBranch
    case git(GitError)
}

extension ProjectCreationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidName(.empty): return "Enter a name."
        case .invalidName(.invalidCharacters): return "Names can't contain “/” or be “.” or “..”."
        case .invalidName(.alreadyExists): return "A folder with that name already exists here."
        case .invalidURL: return "That doesn't look like a repository URL."
        case .invalidBranch: return "That branch name isn't valid."
        case .git(let e): return e.errorDescription
        }
    }
}

/// Creates new project folders and clones repositories. Arguments are always passed as arrays,
/// the clone URL is validated and placed after `--`, so user input can't become a git option.
public struct ProjectCreator: Sendable {
    private let git: GitService

    public init(git: GitService = GitService()) { self.git = git }

    // MARK: - Validation

    public static func validate(name: String, in parent: URL) -> NameError? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        if trimmed == "." || trimmed == ".." || trimmed.contains("/") || trimmed.contains("\0") || trimmed.contains(":") { return .invalidCharacters }
        if FileManager.default.fileExists(atPath: parent.appendingPathComponent(trimmed).path) { return .alreadyExists }
        return nil
    }

    /// Accepts https/http/ssh/git/file URLs, scp-style `user@host:path`, and absolute local paths.
    public static func isAcceptableURL(_ url: String) -> Bool {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty, !u.hasPrefix("-"), !u.contains("::"), !u.contains("\0"), !u.contains("\n") else { return false }
        if u.hasPrefix("/") { return true }
        if let range = u.range(of: "://") {
            return ["https", "http", "ssh", "git", "file"].contains(String(u[u.startIndex..<range.lowerBound]).lowercased())
        }
        return u.range(of: #"^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+:[^\s]+$"#, options: .regularExpression) != nil
    }

    /// "https://github.com/x/y.git" and "git@github.com:x/y.git" → "y".
    public static func repositoryName(from url: String) -> String {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix(".git") { s.removeLast(4) }
        let last = s.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init) ?? ""
        return last
    }

    /// A failed clone removes its half-made folder, except when git refused because the folder already existed:
    /// then it isn't ours to delete.
    static func shouldRemovePartial(after error: Error) -> Bool {
        if case GitError.commandFailed(_, let stderr) = error, stderr.contains("already exists and is not an empty directory") { return false }
        return true
    }

    // MARK: - Creating

    public func createFolder(name: String, in parent: URL, initGit: Bool, defaultBranch: String) async throws -> URL {
        let folder = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = Self.validate(name: folder, in: parent) { throw ProjectCreationError.invalidName(problem) }
        let branch = defaultBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        if initGit && (branch.isEmpty || branch.hasPrefix("-") || branch.contains(" ")) { throw ProjectCreationError.invalidBranch }
        let url = parent.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        if initGit {
            do { try await git.initRepository(at: url, branch: branch) } catch {
                try? FileManager.default.removeItem(at: url)
                throw ProjectCreationError.git((error as? GitError) ?? .commandFailed(code: -1, stderr: error.localizedDescription))
            }
        }
        return url
    }

    public func clone(url: String, name: String, in parent: URL, onLine: @escaping @Sendable (String) -> Void) async throws -> URL {
        guard Self.isAcceptableURL(url) else { throw ProjectCreationError.invalidURL }
        let folder = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = Self.validate(name: folder, in: parent) { throw ProjectCreationError.invalidName(problem) }
        let destination = parent.appendingPathComponent(folder, isDirectory: true)
        do {
            try await git.clone(url: url.trimmingCharacters(in: .whitespacesAndNewlines), into: parent, name: folder, onLine: onLine)
            if Task.isCancelled { throw CancellationError() }
        } catch {
            if Self.shouldRemovePartial(after: error) { try? FileManager.default.removeItem(at: destination) }   // never leave a half-cloned folder
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            throw ProjectCreationError.git((error as? GitError) ?? .commandFailed(code: -1, stderr: error.localizedDescription))
        }
        return destination
    }
}
