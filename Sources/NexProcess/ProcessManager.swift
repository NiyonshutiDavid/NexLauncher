import Foundation
import Observation
import NexCore

public enum ServiceState: Equatable, Sendable {
    case stopped, starting, running(port: Int?), failed(String)

    public var isActive: Bool {
        switch self {
        case .starting, .running: return true
        default: return false
        }
    }
}

/// Identifies one runnable service. `directory` keeps two targets of the same kind
/// (e.g. `web/` and `admin/`, both Vite) apart.
public struct ServiceID: Hashable, Sendable {
    public let projectID: String
    public let kind: ServiceKind
    public let directory: String
    public init(projectID: String, kind: ServiceKind, directory: String = "") {
        self.projectID = projectID
        self.kind = kind
        self.directory = directory
    }
}

/// Spawns `/bin/zsh -lc <command>` in its own session (pgid == pid) with stdout+stderr on one pipe.
public enum ProcessSpawner {
    public static func spawn(command: String, directory: URL, environment: [String: String] = [:]) throws -> (pid: pid_t, fd: Int32) {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { throw POSIXError(.EMFILE) }
        var actions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, fds[1], 1)
        posix_spawn_file_actions_adddup2(&actions, fds[1], 2)
        posix_spawn_file_actions_addclose(&actions, fds[0])
        posix_spawn_file_actions_addclose(&actions, fds[1])
        if #available(macOS 26, *) {
            posix_spawn_file_actions_addchdir(&actions, directory.path)
        } else {
            posix_spawn_file_actions_addchdir_np(&actions, directory.path)   // same call, named _np before macOS 26
        }

        var attrs: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attrs)
        defer { posix_spawnattr_destroy(&attrs) }
        // New session (pgid == pid), and don't leak the app's other descriptors (e.g. git's pipes) into the child.
        posix_spawnattr_setflags(&attrs, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))

        let args = ["/bin/zsh", "-lc", command]
        let cArgs = args.map { strdup($0) } + [nil]
        defer { cArgs.forEach { free($0) } }
        var merged = ProcessInfo.processInfo.environment
        merged.merge(environment) { $1 }
        var cEnv: [UnsafeMutablePointer<CChar>?] = merged.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { cEnv.forEach { free($0) } }
        var pid: pid_t = 0
        let rc = cEnv.withUnsafeMutableBufferPointer { envp in
            posix_spawn(&pid, "/bin/zsh", &actions, &attrs, cArgs, environment.isEmpty ? environ : envp.baseAddress)
        }
        close(fds[1])
        guard rc == 0 else {
            close(fds[0])
            throw POSIXError(POSIXErrorCode(rawValue: rc) ?? .EIO)
        }
        return (pid, fds[0])
    }

    /// Reads lines on a background thread and reaps the process; callbacks arrive off the main thread.
    public static func pump(fd: Int32, pid: pid_t, onLines: @escaping @Sendable ([String]) -> Void, onExit: @escaping @Sendable (Int32) -> Void) {
        let done = DispatchGroup()
        done.enter()
        Thread.detachNewThread {
            var buffer = Data()
            var chunk = [UInt8](repeating: 0, count: 8192)
            while true {
                let n = read(fd, &chunk, chunk.count)
                if n <= 0 { break }
                buffer.append(contentsOf: chunk[0..<n])
                var lines: [String] = []
                while let nl = buffer.firstIndex(of: 0x0A) {
                    lines.append(String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self))
                    buffer.removeSubrange(buffer.startIndex...nl)
                }
                if !lines.isEmpty { onLines(lines) }
            }
            if !buffer.isEmpty { onLines([String(decoding: buffer, as: UTF8.self)]) }
            close(fd)
            done.leave()
        }
        Thread.detachNewThread {
            var status: Int32 = 0
            while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
            killpg(pid, SIGTERM)
            _ = done.wait(timeout: .now() + 1)            // let the last lines arrive first
            onExit((status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f))
        }
    }

    /// SIGTERM to the whole group, then SIGKILL if anything is still alive after the grace period.
    public static func terminateGroup(_ pid: pid_t, grace: TimeInterval = 3) async {
        guard pid > 0 else { return }
        killpg(pid, SIGTERM)
        let deadline = Date().addingTimeInterval(grace)
        while Date() < deadline {
            if killpg(pid, 0) != 0 { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
        killpg(pid, SIGKILL)
    }
}

/// Owns the dev-server processes. Each service runs under `/bin/zsh -lc` in its own session
/// (so pgid == pid), which lets Stop signal the whole tree.
@MainActor @Observable
public final class ProcessManager {
    public private(set) var states: [ServiceID: ServiceState] = [:]
    public private(set) var logs: [ServiceID: [String]] = [:]
    public var onChange: (@MainActor () -> Void)?
    /// How to stop a compose stack; `docker compose up` doesn't stop its containers when killed.
    public var dockerStopCommand: (URL) -> String = { "cd \(CommandBuilder.quote($0.path)) && docker compose stop" }

    public static let maxLogLines = 5000
    private let killTimeout: TimeInterval
    private var pids: [ServiceID: pid_t] = [:]
    private var directories: [ServiceID: URL] = [:]
    private var fixedPorts: [ServiceID: Int] = [:]
    private var stopRequested: Set<ServiceID> = []
    private var userStopped: Set<ServiceID> = []

    public init(killTimeout: TimeInterval = 3) {
        self.killTimeout = killTimeout
    }

    public var runningCount: Int { states.values.filter(\.isActive).count }

    public func wasUserStopped(_ id: ServiceID) -> Bool { userStopped.contains(id) }

    public static func id(for target: ServiceTarget, projectID: String) -> ServiceID {
        ServiceID(projectID: projectID, kind: target.kind, directory: target.directory.path)
    }

    // MARK: - Start

    public func start(_ target: ServiceTarget, projectID: String) {
        let id = Self.id(for: target, projectID: projectID)
        if states[id]?.isActive == true { return }
        logs[id] = []
        stopRequested.remove(id)
        userStopped.remove(id)
        directories[id] = target.directory
        fixedPorts[id] = target.port

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.directory.path, isDirectory: &isDir), isDir.boolValue else {
            set(id, .failed("Folder not found: \(target.directory.path)"))
            return
        }
        do {
            let (pid, readFD) = try ProcessSpawner.spawn(command: target.command, directory: target.directory)
            pids[id] = pid
            set(id, .starting)
            Self.pump(readFD: readFD, pid: pid, id: id, manager: self)
        } catch {
            set(id, .failed("Could not start: \(error.localizedDescription)"))
        }
    }

    /// Reader thread feeds log lines to the main actor; a second thread reaps the process.
    private nonisolated static func pump(readFD: Int32, pid: pid_t, id: ServiceID, manager: ProcessManager) {
        Thread.detachNewThread {
            var buffer = Data()
            var chunk = [UInt8](repeating: 0, count: 8192)
            while true {
                let n = read(readFD, &chunk, chunk.count)
                if n <= 0 { break }
                buffer.append(contentsOf: chunk[0..<n])
                var lines: [String] = []
                while let nl = buffer.firstIndex(of: 0x0A) {
                    lines.append(String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self))
                    buffer.removeSubrange(buffer.startIndex...nl)
                }
                if !lines.isEmpty { let batch = lines; Task { @MainActor in manager.append(batch, to: id, pid: pid) } }
            }
            if !buffer.isEmpty { let tail = String(decoding: buffer, as: UTF8.self); Task { @MainActor in manager.append([tail], to: id, pid: pid) } }
            close(readFD)
        }
        Thread.detachNewThread {
            var status: Int32 = 0
            while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
            killpg(pid, SIGTERM)          // don't leave stragglers from a shell that has exited
            Thread.sleep(forTimeInterval: 0.15)   // let the reader drain final lines first
            let code = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
            Task { @MainActor in manager.handleExit(id, pid: pid, code: code) }
        }
    }

    // MARK: - Main-actor callbacks

    private func append(_ lines: [String], to id: ServiceID, pid: pid_t) {
        guard pids[id] == pid else { return }          // output from an earlier run of this service
        var current = logs[id] ?? []
        current.append(contentsOf: lines)
        if current.count > Self.maxLogLines { current.removeFirst(current.count - Self.maxLogLines) }
        logs[id] = current
        guard let state = states[id], state.isActive else { return }
        if let fixed = fixedPorts[id] { set(id, .running(port: fixed)); return }
        if case .running(let port?) = state { return }  // the first port announced wins
        if let port = lines.lazy.compactMap(PortParser.port(in:)).first { set(id, .running(port: port)) }
        else if state == .starting { set(id, .running(port: nil)) }
    }

    private func handleExit(_ id: ServiceID, pid: pid_t, code: Int32) {
        guard pids[id] == pid else { return }
        pids[id] = nil
        let wasStopped = stopRequested.remove(id) != nil
        if wasStopped || code == 0 {
            set(id, .stopped)
        } else {
            let last = logs[id]?.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
            set(id, .failed("Exited with code \(code)" + (last.isEmpty ? "" : ": \(last)")))
        }
    }

    private func set(_ id: ServiceID, _ state: ServiceState) {
        guard states[id] != state else { return }
        states[id] = state
        onChange?()
    }

    // MARK: - Stop

    public func stop(_ id: ServiceID) async {
        guard let pid = pids[id] else { return }
        stopRequested.insert(id)
        userStopped.insert(id)
        killpg(pid, SIGTERM)
        if id.kind == .docker, let dir = directories[id] { await runShell(dockerStopCommand(dir), timeout: 60) }
        // Done only when the leader is reaped AND nothing is left in its group; otherwise escalate.
        let deadline = Date().addingTimeInterval(killTimeout)
        while Date() < deadline {
            if pids[id] != pid && killpg(pid, 0) != 0 { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        killpg(pid, SIGKILL)
        let reapDeadline = Date().addingTimeInterval(2)
        while pids[id] == pid && Date() < reapDeadline { try? await Task.sleep(for: .milliseconds(20)) }
    }

    public func stopAll() async {
        for id in Array(pids.keys) { await stop(id) }
    }

    private func runShell(_ command: String, timeout: TimeInterval) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-lc", command]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            p.terminationHandler = { _ in cont.resume() }
            do { try p.run() } catch { cont.resume(); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } }
        }
    }
}
