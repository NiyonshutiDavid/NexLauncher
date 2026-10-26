import Foundation

public struct GitResult: Sendable {
    public let code: Int32
    public let stdout: String
    public let stderr: String
}

/// Runs `/usr/bin/git` with an argument array (never through a shell).
public struct GitRunner: Sendable {
    private let extraEnvironment: [String: String]
    var extraEnvironmentForStream: [String: String] { extraEnvironment }

    public init(extraEnvironment: [String: String] = [:]) {
        self.extraEnvironment = extraEnvironment
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
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = args
            p.currentDirectoryURL = dir
            var environment = ProcessInfo.processInfo.environment
            environment["GIT_TERMINAL_PROMPT"] = "0"
            environment["GIT_EDITOR"] = "true"
            environment["LC_ALL"] = "C"
            environment["GIT_LITERAL_PATHSPECS"] = "1"   // paths are file names, never globs ([id], *, ?)
            environment.merge(env) { $1 }
            p.environment = environment
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            p.standardInput = FileHandle.nullDevice

            // Event-driven (no blocked threads) so many concurrent git calls can't starve GCD.
            let state = RunState(cont)
            // A pipe is drained when its handler sees an empty read (EOF); we finish once both pipes
            // are drained AND the process has exited, so no output can be lost to a race.
            out.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil; state.outDrained() } else { state.appendOut(d) }
            }
            err.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil; state.errDrained() } else { state.appendErr(d) }
            }
            p.terminationHandler = { proc in state.exited(code: proc.terminationStatus) }
            do { try p.run() } catch {
                state.fail(GitError.commandFailed(code: -1, stderr: error.localizedDescription))
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                // Fires even if git already exited but a child still holds the pipe open.
                if p.isRunning { p.terminate() }
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
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                p.arguments = args
                p.currentDirectoryURL = dir
                var environment = ProcessInfo.processInfo.environment
                environment["GIT_TERMINAL_PROMPT"] = "0"
                environment["GIT_EDITOR"] = "true"
                environment["LC_ALL"] = "C"
                environment["GIT_LITERAL_PATHSPECS"] = "1"
                environment.merge(extraEnvironmentForStream) { $1 }
                p.environment = environment
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                p.standardInput = FileHandle.nullDevice
                box.process = p
                box.continuation = cont
                pipe.fileHandleForReading.readabilityHandler = { h in
                    let d = h.availableData
                    if d.isEmpty { h.readabilityHandler = nil; box.drained(); return }
                    for line in box.split(d) { onLine(line) }
                }
                p.terminationHandler = { proc in box.exited(proc.terminationStatus) }
                do { try p.run() } catch {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    box.fail(GitError.commandFailed(code: -1, stderr: error.localizedDescription))
                    return
                }
                if Task.isCancelled { p.terminate() }
            }
        } onCancel: {
            box.cancel()
        }
    }
}

private final class StreamBox: @unchecked Sendable {
    private let lock = NSLock()
    var process: Process?
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
    func exited(_ code: Int32) { lock.lock(); status = code; lock.unlock(); tryFinish() }
    func cancel() { lock.lock(); let p = process; lock.unlock(); if p?.isRunning == true { p?.terminate() } }

    private func tryFinish() {
        lock.lock(); defer { lock.unlock() }
        guard drainedFlag, let status, let c = continuation else { return }
        continuation = nil
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

    init(_ cont: CheckedContinuation<GitResult, Error>) { self.cont = cont }

    func appendOut(_ d: Data) { lock.lock(); out.append(d); lock.unlock() }
    func appendErr(_ d: Data) { lock.lock(); err.append(d); lock.unlock() }
    func outDrained() { lock.lock(); outDone = true; lock.unlock(); tryFinish() }
    func errDrained() { lock.lock(); errDone = true; lock.unlock(); tryFinish() }
    func exited(code: Int32) { lock.lock(); self.code = code; lock.unlock(); tryFinish() }

    private func tryFinish() {
        lock.lock(); defer { lock.unlock() }
        guard outDone, errDone, let code, let c = cont else { return }
        cont = nil
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
