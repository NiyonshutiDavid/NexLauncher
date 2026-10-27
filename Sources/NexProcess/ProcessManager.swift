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

#if os(Linux)
private typealias SpawnActions = posix_spawn_file_actions_t
private typealias SpawnAttrs = posix_spawnattr_t
private let spawnSetSID: Int32 = 0x80          // POSIX_SPAWN_SETSID in glibc, not exported to Swift
#else
private typealias SpawnActions = posix_spawn_file_actions_t?
private typealias SpawnAttrs = posix_spawnattr_t?
#endif

/// Spawns a login shell running `<command>` in its own session (pgid == pid) with stdout+stderr on one pipe:
/// `/bin/zsh -lc` on macOS, the user's shell on Linux, through `flatpak-spawn --host` inside a Flatpak.
public enum ProcessSpawner {
    public static func spawn(command: String, directory: URL, environment: [String: String] = [:]) throws -> (pid: pid_t, fd: Int32) {
        let invocation = HostCommand.service(command, in: directory, environment: environment)
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { throw POSIXError(.EMFILE) }
        #if os(Linux)
        var actions = SpawnActions()
        #else
        var actions: SpawnActions = nil
        #endif
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, fds[1], 1)
        posix_spawn_file_actions_adddup2(&actions, fds[1], 2)
        posix_spawn_file_actions_addclose(&actions, fds[0])
        posix_spawn_file_actions_addclose(&actions, fds[1])
        #if os(Linux)
        posix_spawn_file_actions_addchdir_np(&actions, directory.path)
        posix_spawn_file_actions_addclosefrom_np(&actions, 3)    // don't leak the app's other descriptors
        #else
        if #available(macOS 26, *) {
            posix_spawn_file_actions_addchdir(&actions, directory.path)
        } else {
            posix_spawn_file_actions_addchdir_np(&actions, directory.path)   // same call, named _np before macOS 26
        }
        #endif

        #if os(Linux)
        var attrs = SpawnAttrs()
        #else
        var attrs: SpawnAttrs = nil
        #endif
        posix_spawnattr_init(&attrs)
        defer { posix_spawnattr_destroy(&attrs) }
        // New session (pgid == pid), and don't leak the app's other descriptors (e.g. git's pipes) into the child.
        #if os(Linux)
        PipedSpawn.resetSignals(&attrs, flags: Int16(spawnSetSID))
        #else
        posix_spawnattr_setflags(&attrs, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))
        #endif

        let args = [invocation.executable] + invocation.arguments
        let cArgs = args.map { strdup($0) } + [nil]
        defer { cArgs.forEach { free($0) } }
        var merged = ProcessInfo.processInfo.environment
        merged.merge(invocation.environment) { $1 }
        var cEnv: [UnsafeMutablePointer<CChar>?] = merged.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { cEnv.forEach { free($0) } }
        var pid: pid_t = 0
        let rc = cEnv.withUnsafeMutableBufferPointer { envp in
            posix_spawn(&pid, invocation.executable, &actions, &attrs, cArgs, invocation.environment.isEmpty ? environ : envp.baseAddress)
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
                lines = takeHostPGID(from: lines, pid: pid)
                if !lines.isEmpty { onLines(lines) }
            }
            if !buffer.isEmpty { onLines(takeHostPGID(from: [String(decoding: buffer, as: UTF8.self)], pid: pid)) }
            close(fd)
            done.leave()
        }
        Thread.detachNewThread {
            var status: Int32 = 0
            while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
            signalGroup(pid, SIGTERM)
            _ = done.wait(timeout: .now() + 1)            // let the last lines arrive first
            forgetHostPGID(pid)
            onExit((status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f))
        }
    }

    /// SIGTERM to the whole group, then SIGKILL if anything is still alive after the grace period.
    public static func terminateGroup(_ pid: pid_t, grace: TimeInterval = 3) async {
        guard pid > 0 else { return }
        signalGroup(pid, SIGTERM)
        let deadline = Date().addingTimeInterval(grace)
        while Date() < deadline {
            if !groupAlive(pid) { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
        signalGroup(pid, SIGKILL)
    }

    // MARK: - Process groups on the host (Flatpak)

    private static let hostLock = NSLock()
    nonisolated(unsafe) private static var hostPGIDs: [pid_t: Int32] = [:]
    /// Runs `flatpak-spawn` with these arguments and returns its exit code (replaced in tests).
    nonisolated(unsafe) public static var hostRunner: ([String]) -> Int32 = { args in
        let p = Process()
        p.executableURL = URL(fileURLWithPath: HostCommand.flatpakSpawn)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    /// Removes a leading `NEXPGID=<n>` line (printed by the Flatpak host shell) and remembers the group for `pid`.
    public static func takeHostPGID(from lines: [String], pid: pid_t) -> [String] {
        guard let first = lines.first, first.hasPrefix("NEXPGID="), let pgid = Int32(first.dropFirst(8)) else { return lines }
        hostLock.lock(); hostPGIDs[pid] = pgid; hostLock.unlock()
        return Array(lines.dropFirst())
    }

    public static func hostPGID(for pid: pid_t) -> Int32? {
        hostLock.lock(); defer { hostLock.unlock() }
        return hostPGIDs[pid]
    }

    static func forgetHostPGID(_ pid: pid_t) {
        hostLock.lock(); hostPGIDs[pid] = nil; hostLock.unlock()
    }

    /// Signals the local group and, for a Flatpak service, the host group it started.
    public static func signalGroup(_ pid: pid_t, _ signal: Int32) {
        killpg(pid, signal)
        guard let pgid = hostPGID(for: pid) else { return }
        let name = signal == SIGKILL ? "-KILL" : signal == 0 ? "-0" : "-TERM"
        _ = hostRunner(["--host", "kill", name, "--", "-\(pgid)"])
    }

    /// Whether anything in the group (locally, and on the host for Flatpak services) is still running.
    public static func groupAlive(_ pid: pid_t) -> Bool {
        if let pgid = hostPGID(for: pid) { return hostRunner(["--host", "kill", "-0", "--", "-\(pgid)"]) == 0 }
        return killpg(pid, 0) == 0
    }
}

/// Owns the dev-server processes. Each service runs in a login shell in its own session
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
                lines = ProcessSpawner.takeHostPGID(from: lines, pid: pid)
                if !lines.isEmpty { let batch = lines; Task { @MainActor in manager.append(batch, to: id, pid: pid) } }
            }
            if !buffer.isEmpty {
                let tail = ProcessSpawner.takeHostPGID(from: [String(decoding: buffer, as: UTF8.self)], pid: pid)
                if !tail.isEmpty { Task { @MainActor in manager.append(tail, to: id, pid: pid) } }
            }
            close(readFD)
        }
        Thread.detachNewThread {
            var status: Int32 = 0
            while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
            ProcessSpawner.signalGroup(pid, SIGTERM)   // don't leave stragglers from a shell that has exited
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
        ProcessSpawner.signalGroup(pid, SIGTERM)
        if id.kind == .docker, let dir = directories[id] { await runShell(dockerStopCommand(dir), timeout: 60) }
        // Done only when the leader is reaped AND nothing is left in its group; otherwise escalate.
        let deadline = Date().addingTimeInterval(killTimeout)
        while Date() < deadline {
            if pids[id] != pid && !ProcessSpawner.groupAlive(pid) { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        ProcessSpawner.signalGroup(pid, SIGKILL)
        let reapDeadline = Date().addingTimeInterval(2)
        while pids[id] == pid && Date() < reapDeadline { try? await Task.sleep(for: .milliseconds(20)) }
    }

    public func stopAll() async {
        for id in Array(pids.keys) { await stop(id) }
    }

    private func runShell(_ command: String, timeout: TimeInterval) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let p = Process()
            let invocation = HostCommand.service(command, in: URL(fileURLWithPath: NSHomeDirectory()), environment: [:])
            p.executableURL = URL(fileURLWithPath: invocation.executable)
            p.arguments = invocation.arguments
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            p.terminationHandler = { _ in cont.resume() }
            do { try p.run() } catch { cont.resume(); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } }
        }
    }
}
