import Foundation
import NexCore
#if canImport(Glibc)
import Glibc
#endif

public struct GitResult: Sendable {
    public let code: Int32
    public let stdout: String
    public let stderr: String
}

/// Runs git from PATH with an argument array (never through a shell); inside a Flatpak, the host's git.
public struct GitRunner: Sendable {
    private let extraEnvironment: [String: String]
    var extraEnvironmentForStream: [String: String] { extraEnvironment }

    public init(extraEnvironment: [String: String] = [:]) {
        self.extraEnvironment = extraEnvironment
    }

    /// How git is started for `args` in `dir`.
    public static func invocation(_ args: [String], in dir: URL, environment: [String: String], flatpak: Bool) -> HostInvocation {
        HostCommand.exec("git", args, in: dir, environment: environment, flatpak: flatpak)
    }

    /// The variables every git call gets: no prompts or editors, plain English output, literal paths.
    static func gitEnvironment(_ extra: [String: String]) -> [String: String] {
        var env = ["GIT_TERMINAL_PROMPT": "0", "GIT_EDITOR": "true", "LC_ALL": "C",
                   "GIT_LITERAL_PATHSPECS": "1"]   // paths are file names, never globs ([id], *, ?)
        env.merge(extra) { $1 }
        return env
    }

    /// Configures `p` to run git with `args` in `dir`.
    static func configure(_ p: Process, args: [String], dir: URL, extra: [String: String]) {
        let inv = invocation(args, in: dir, environment: gitEnvironment(extra), flatpak: Platform.isFlatpak)
        p.executableURL = URL(fileURLWithPath: inv.executable)
        p.arguments = inv.arguments
        p.currentDirectoryURL = dir
        var environment = ProcessInfo.processInfo.environment
        environment.merge(inv.environment) { $1 }
        p.environment = environment
    }

    /// Starts git with stdin from /dev/null; `onExit` gets the exit status. Without `mergeStderr`, stderr has its
    /// own handle. On Linux git is started directly (see `PipedSpawn`), elsewhere through `Process`.
    static func launch(_ args: [String], in dir: URL, extra: [String: String], mergeStderr: Bool,
                       onExit: @escaping @Sendable (Int32) -> Void) throws -> GitLaunch {
        #if os(Linux)
        let inv = invocation(args, in: dir, environment: gitEnvironment(extra), flatpak: Platform.isFlatpak)
        let child = try PipedSpawn.start(inv, in: dir, mergeStderr: mergeStderr)
        let exit = ExitFlag()
        PipedSpawn.onExit(child.pid) { code in exit.set(); onExit(code) }
        return GitLaunch(out: FileHandle(fileDescriptor: child.stdout, closeOnDealloc: true),
                         err: child.stderr.map { FileHandle(fileDescriptor: $0, closeOnDealloc: true) },
                         terminate: { if !exit.isSet { kill(child.pid, SIGTERM) } },
                         isRunning: { !exit.isSet })
        #else
        let p = Process()
        configure(p, args: args, dir: dir, extra: extra)
        let out = Pipe(), err = mergeStderr ? nil : Pipe()
        p.standardOutput = out
        p.standardError = err ?? out
        p.standardInput = FileHandle.nullDevice
        p.terminationHandler = { proc in onExit(proc.terminationStatus) }
        try p.run()
        return GitLaunch(out: out.fileHandleForReading, err: err?.fileHandleForReading,
                         terminate: { if p.isRunning { p.terminate() } }, isRunning: { p.isRunning })
        #endif
    }

    /// Returns stdout, throwing `.commandFailed` on a non-zero exit.
    public func run(_ args: [String], in dir: URL, timeout: TimeInterval = 30) async throws -> String {
        let result = try await runRaw(args, in: dir, timeout: timeout)
        guard result.code == 0 else {
            throw GitError.commandFailed(code: result.code, stderr: result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        return result.stdout
    }

    public func runRaw(_ args: [String], in dir: URL, timeout: TimeInterval = 30) async throws -> GitResult {
        let env = extraEnvironment
        return try await withCheckedThrowingContinuation { cont in
            // Event-driven (no blocked threads) so many concurrent git calls can't starve GCD.
            let state = RunState(cont)
            let git: GitLaunch
            do {
                git = try Self.launch(args, in: dir, extra: env, mergeStderr: false) { state.exited(code: $0) }
            } catch {
                state.fail(GitError.commandFailed(code: -1, stderr: error.localizedDescription))
                return
            }
            // A pipe is drained when its handler sees an empty read (EOF); we finish once both pipes
            // are drained AND the process has exited, so no output can be lost to a race. A child git leaves
            // behind can hold the pipes open, so a second after git exits the call finishes with what was read.
            state.handles = [git.out, git.err!]
            git.out.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil; state.outDrained() } else { state.appendOut(d) }
            }
            git.err!.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil; state.errDrained() } else { state.appendErr(d) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                // Fires even if git already exited but a child still holds the pipe open.
                git.terminate()
                state.fail(GitError.timeout)
            }
        }
    }
}

extension GitRunner {
    /// Runs git and delivers output lines (stdout and stderr combined; `\r` progress updates count as lines)
    /// as they arrive. Cancelling the calling Task terminates git. Returns the exit status.
    public func stream(_ args: [String], in dir: URL, onLine: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        let box = StreamBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int32, Error>) in
                box.continuation = cont
                let git: GitLaunch
                do {
                    git = try Self.launch(args, in: dir, extra: extraEnvironmentForStream, mergeStderr: true) { box.exited($0) }
                } catch {
                    box.fail(GitError.commandFailed(code: -1, stderr: error.localizedDescription))
                    return
                }
                box.git = git
                git.out.readabilityHandler = { h in
                    let d = h.availableData
                    if d.isEmpty { h.readabilityHandler = nil; box.drained(); return }
                    for line in box.split(d) { onLine(line) }
                }
                if Task.isCancelled { git.terminate() }
            }
        } onCancel: {
            box.cancel()
        }
    }
}

struct GitLaunch: @unchecked Sendable {
    let out: FileHandle
    let err: FileHandle?
    let terminate: @Sendable () -> Void
    let isRunning: @Sendable () -> Bool
}

final class ExitFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

private final class StreamBox: @unchecked Sendable {
    private let lock = NSLock()
    var git: GitLaunch?
    var continuation: CheckedContinuation<Int32, Error>?
    private var pending = Data()
    private var drainedFlag = false, status: Int32?

    /// Splits on \n and \r, keeping any incomplete tail for the next chunk.
    func split(_ data: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        pending.append(data)
        var lines: [String] = []
        while let i = pending.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let line = String(decoding: pending[pending.startIndex..<i], as: UTF8.self)
            pending.removeSubrange(pending.startIndex...i)
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }
    func drained() { lock.lock(); drainedFlag = true; lock.unlock(); tryFinish() }

    /// Git has exited. On Linux, Foundation doesn't always report end-of-output after that, so the call also
    /// finishes a second later without it (by then every line git wrote has been read).
    func exited(_ code: Int32) {
        lock.lock(); status = code; lock.unlock()
        tryFinish()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [self] in finish(requireDrained: false) }
    }

    func cancel() {
        lock.lock(); let git = git; lock.unlock()
        if git?.isRunning() == true { git?.terminate() } else { fail(CancellationError()) }
    }

    private func tryFinish() { finish(requireDrained: true) }

    private func finish(requireDrained: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard drainedFlag || !requireDrained, let status, let c = continuation else { return }
        continuation = nil
        git?.out.readabilityHandler = nil
        c.resume(returning: status)
    }
    func fail(_ error: Error) {
        lock.lock(); defer { lock.unlock() }
        guard let c = continuation else { return }
        continuation = nil
        c.resume(throwing: error)
    }
}

private final class RunState: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<GitResult, Error>?
    private var out = Data(), err = Data()
    private var outDone = false, errDone = false, code: Int32?
    /// Stops reading when the call finishes (a lingering child may never close the pipes).
    var handles: [FileHandle] = []

    init(_ cont: CheckedContinuation<GitResult, Error>) { self.cont = cont }

    func appendOut(_ d: Data) { lock.lock(); out.append(d); lock.unlock() }
    func appendErr(_ d: Data) { lock.lock(); err.append(d); lock.unlock() }
    func outDrained() { lock.lock(); outDone = true; lock.unlock(); tryFinish() }
    func errDrained() { lock.lock(); errDone = true; lock.unlock(); tryFinish() }
    func exited(code: Int32) {
        lock.lock(); self.code = code; lock.unlock()
        tryFinish()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [self] in finish(requireDrained: false) }
    }

    private func tryFinish() { finish(requireDrained: true) }

    private func finish(requireDrained: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard (outDone && errDone) || !requireDrained, let code, let c = cont else { return }
        cont = nil
        handles.forEach { $0.readabilityHandler = nil }
        c.resume(returning: GitResult(
            code: code,
            stdout: String(decoding: out, as: UTF8.self),
            stderr: String(decoding: err, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    func fail(_ error: Error) {
        lock.lock(); defer { lock.unlock() }
        guard let c = cont else { return }
        cont = nil
        c.resume(throwing: error)
    }
}
