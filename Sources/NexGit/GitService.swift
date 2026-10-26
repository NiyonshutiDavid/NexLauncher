import Foundation

public struct GitService: Sendable {
    let runner: GitRunner

    public init(runner: GitRunner = GitRunner()) {
        self.runner = runner
    }

    static let skipNames: Set<String> = ["node_modules", ".dart_tool", "build", "dist", ".next", "venv", ".venv", "Pods"]

    // MARK: - Discovery

    /// Repositories at or below `project` (three levels deep). A repo is a leaf: nested repos inside it are not listed.
    public func findRepos(under project: URL) -> [URL] {
        var found: [URL] = []
        func walk(_ dir: URL, depth: Int) {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path) {
                found.append(dir)
                return
            }
            guard depth < 3, let kids = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
            for kid in kids.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where !Self.skipNames.contains(kid.lastPathComponent)
                && (try? kid.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                walk(kid, depth: depth + 1)
            }
        }
        walk(project, depth: 0)
        return found
    }

    // MARK: - Reading

    func git(_ args: [String], _ repo: URL, timeout: TimeInterval = 30) async throws -> String {
        do {
            return try await runner.run(args, in: repo, timeout: timeout)
        } catch GitError.commandFailed(_, let stderr) where stderr.contains("not a git repository") {
            throw GitError.notARepo
        }
    }

    public func status(_ repo: URL) async throws -> RepoStatus {
        let raw = try await git(["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all"], repo)
        var branch: String?, upstream: String?, ahead = 0, behind = 0, detached = false, hasCommits = true
        var changes: [FileChange] = []
        var entries = raw.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)[...]
        while let entry = entries.popFirst() {
            if entry.hasPrefix("# branch.oid") {
                hasCommits = !entry.hasSuffix("(initial)")
            } else if entry.hasPrefix("# branch.head ") {
                let name = String(entry.dropFirst("# branch.head ".count))
                if name == "(detached)" { detached = true } else { branch = name }
            } else if entry.hasPrefix("# branch.upstream ") {
                upstream = String(entry.dropFirst("# branch.upstream ".count))
            } else if entry.hasPrefix("# branch.ab ") {
                let parts = entry.dropFirst("# branch.ab ".count).split(separator: " ")
                if parts.count == 2 { ahead = Int(parts[0].dropFirst()) ?? 0; behind = Int(parts[1].dropFirst()) ?? 0 }
            } else if entry.hasPrefix("? ") {
                changes.append(FileChange(path: String(entry.dropFirst(2)), index: "?", worktree: "?"))
            } else if entry.hasPrefix("1 ") || entry.hasPrefix("u ") {
                let fields = entry.split(separator: " ", maxSplits: entry.hasPrefix("1 ") ? 8 : 10, omittingEmptySubsequences: false)
                let xy = Array(fields[1])
                changes.append(FileChange(path: String(fields.last!), index: xy[0], worktree: xy[1]))
            } else if entry.hasPrefix("2 ") {
                let fields = entry.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
                let xy = Array(fields[1])
                changes.append(FileChange(path: String(fields.last!), index: xy[0], worktree: xy[1]))
                _ = entries.popFirst()   // original path of the rename
            }
        }
        return RepoStatus(branch: branch, upstream: upstream, ahead: ahead, behind: behind,
                          changes: changes, isDetached: detached, hasCommits: hasCommits)
    }

    public func diff(_ repo: URL, file: FileChange) async throws -> String {
        if file.isUntracked {
            let r = try await runner.runRaw(["diff", "--no-index", "--", "/dev/null", file.path], in: repo)
            return r.stdout
        }
        let args = file.isStaged && file.worktree == "." ? ["diff", "--cached", "--", file.path] : ["diff", "HEAD", "--", file.path]
        do { return try await git(args, repo) } catch GitError.commandFailed {
            return try await git(["diff", "--cached", "--", file.path], repo)   // no HEAD yet
        }
    }

    public func log(_ repo: URL, limit: Int) async throws -> [CommitInfo] {
        let out: String
        do { out = try await git(["log", "-n", "\(limit)", "--format=%H%x1f%s%x1f%an%x1f%at"], repo) } catch GitError.commandFailed { return [] }
        return out.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 4, let t = TimeInterval(f[3]) else { return nil }
            return CommitInfo(id: f[0], subject: f[1], author: f[2], date: Date(timeIntervalSince1970: t))
        }
    }

    public func branches(_ repo: URL) async throws -> [String] {
        try await git(["branch", "--format=%(refname:short)"], repo).split(separator: "\n").map(String.init)
    }

    // MARK: - Identity

    private func scopeFlag(_ scope: GitScope) -> String { scope == .global ? "--global" : "--local" }

    private func config(_ key: String, _ repo: URL, scope: GitScope?) async throws -> String? {
        var args = ["config"]
        if let scope { args.append(scopeFlag(scope)) }
        let r = try await runner.runRaw(args + ["--get", key], in: repo)
        let value = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.code == 0 && !value.isEmpty ? value : nil
    }

    public func identity(_ repo: URL, scope: GitScope) async throws -> GitIdentity {
        GitIdentity(name: try await config("user.name", repo, scope: scope), email: try await config("user.email", repo, scope: scope))
    }

    /// The identity git would actually use (repo, then global).
    public func effectiveIdentity(_ repo: URL) async throws -> GitIdentity {
        GitIdentity(name: try await config("user.name", repo, scope: nil), email: try await config("user.email", repo, scope: nil))
    }

    public func setIdentity(_ id: GitIdentity, repo: URL, scope: GitScope) async throws {
        if let name = id.name { _ = try await git(["config", scopeFlag(scope), "user.name", name], repo) }
        if let email = id.email { _ = try await git(["config", scopeFlag(scope), "user.email", email], repo) }
    }
}
