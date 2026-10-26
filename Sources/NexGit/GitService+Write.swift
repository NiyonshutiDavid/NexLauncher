import Foundation

extension GitService {
    // MARK: - Error mapping

    /// Maps raw git output to a typed error. Auth failures are recognised by their well-known messages.
    static func classify(_ output: String, code: Int32 = 1) -> GitError {
        let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let authMarkers = ["Authentication failed", "Permission denied (publickey)", "could not read Username",
                           "could not read Password", "Invalid username or password", "Repository not found"]
        // Markers are in priority order so the most specific line is reported.
        for marker in authMarkers { if let line = lines.first(where: { $0.contains(marker) }) { return .authFailed(line) } }
        if output.contains("Not possible to fast-forward") { return .cannotFastForward }
        if output.contains("not a git repository") { return .notARepo }
        return .commandFailed(code: code, stderr: output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func run(_ args: [String], _ repo: URL, timeout: TimeInterval = 30) async throws {
        let r = try await runner.runRaw(args, in: repo, timeout: timeout)
        guard r.code == 0 else { throw Self.classify(r.stderr.isEmpty ? r.stdout : r.stderr, code: r.code) }
    }

    // MARK: - Staging

    public func stage(_ repo: URL, paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        try await run(["add", "--"] + paths, repo)
    }

    public func unstage(_ repo: URL, paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        if try await status(repo).hasCommits {
            try await run(["restore", "--staged", "--"] + paths, repo)
        } else {
            try await run(["rm", "--cached", "-r", "--"] + paths, repo)
        }
    }

    /// Reverts tracked files to HEAD and deletes untracked files — only the listed paths.
    public func discard(_ repo: URL, paths: [String]) async throws {
        let current = try await status(repo)
        let untracked = Set(current.changes.filter(\.isUntracked).map(\.path))
        let tracked = paths.filter { !untracked.contains($0) }
        let doomed = paths.filter { untracked.contains($0) }
        if !tracked.isEmpty { try await run(["restore", "--source=HEAD", "--staged", "--worktree", "--"] + tracked, repo) }
        if !doomed.isEmpty { try await run(["clean", "-f", "--"] + doomed, repo) }
    }

    // MARK: - Commit

    public func commit(_ repo: URL, summary: String, description: String) async throws {
        let subject = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty else { throw GitError.emptyMessage }
        let staged = try await runner.runRaw(["diff", "--cached", "--quiet"], in: repo)
        guard staged.code == 1 else {
            if staged.code == 0 { throw GitError.nothingToCommit }
            throw Self.classify(staged.stderr, code: staged.code)
        }
        var args = ["commit", "-m", subject]
        let body = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty { args += ["-m", body] }
        try await run(args, repo)
    }

    // MARK: - Remote

    public func fetch(_ repo: URL) async throws {
        try await run(["fetch", "--prune"], repo, timeout: 120)
    }

    public func pull(_ repo: URL, strategy: PullStrategy) async throws {
        guard try await status(repo).upstream != nil else { throw GitError.noUpstream }
        let flag: String
        switch strategy {
        case .ffOnly: flag = "--ff-only"
        case .merge: flag = "--no-rebase"
        case .rebase: flag = "--rebase"
        }
        let r = try await runner.runRaw(["pull", flag], in: repo, timeout: 120)
        guard r.code != 0 else { return }
        let output = r.stderr.isEmpty ? r.stdout : r.stderr + "\n" + r.stdout
        let unmerged = try await runner.runRaw(["diff", "--name-only", "--diff-filter=U"], in: repo)
        let files = unmerged.stdout.split(separator: "\n").map(String.init)
        if !files.isEmpty { throw GitError.conflicts(files) }   // left in place so they can be resolved
        throw Self.classify(output, code: r.code)
    }

    /// Pushes the current branch (setting upstream if needed). Never forces.
    public func push(_ repo: URL) async throws {
        let s = try await status(repo)
        guard let branch = s.branch else {
            throw GitError.commandFailed(code: -1, stderr: "Can't push from a detached HEAD. Switch to a branch first.")
        }
        let args = s.upstream == nil ? ["push", "-u", "origin", branch] : ["push"]
        try await run(args, repo, timeout: 120)
    }

    // MARK: - Branches

    public func switchBranch(_ repo: URL, to name: String) async throws {
        try await run(["switch", name], repo)
    }

    public func createBranch(_ repo: URL, named name: String) async throws {
        try await run(["switch", "-c", name], repo)
    }
}

extension GitService {
    public func initRepository(at dir: URL, branch: String) async throws {
        try await run(["init", "--initial-branch=\(branch)"], dir)
    }

    /// `git clone --progress -- <url> <name>` inside `parent`, streaming output lines.
    public func clone(url: String, into parent: URL, name: String, onLine: @escaping @Sendable (String) -> Void) async throws {
        var collected: [String] = []
        let lock = NSLock()
        let code = try await runner.stream(["clone", "--progress", "--", url, name], in: parent) { line in
            lock.lock(); collected.append(line); lock.unlock()
            onLine(line)
        }
        if Task.isCancelled { throw CancellationError() }
        guard code == 0 else {
            lock.lock(); let text = collected.suffix(6).joined(separator: "\n"); lock.unlock()
            throw Self.classify(text, code: code)
        }
    }
}
