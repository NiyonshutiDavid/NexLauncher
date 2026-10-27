import Foundation
#if canImport(Glibc)
import Glibc
#endif

/// The PATH (and tool-manager variables) of the user's interactive login shell. Installers such as nvm, pyenv and
/// asdf add themselves to ~/.bashrc, which Ubuntu's stock copy skips for non-interactive shells, so `-lc` alone
/// misses them. Read once at startup, as editors do, and passed to every host command.
public enum ShellEnvironment {
    private static let keptNames: Set<String> = [
        "PATH", "NVM_DIR", "NVM_BIN", "PYENV_ROOT", "ASDF_DIR", "ASDF_DATA_DIR", "VOLTA_HOME", "BUN_INSTALL",
        "PNPM_HOME", "DENO_INSTALL", "GOPATH", "GOROOT", "CARGO_HOME", "RUSTUP_HOME", "JAVA_HOME", "SDKMAN_DIR",
        "ANDROID_HOME", "ANDROID_SDK_ROOT", "FLUTTER_ROOT", "PUB_CACHE", "GEM_HOME", "GEM_PATH", "RBENV_ROOT",
    ]

    /// Parses `env -0` output.
    public static func parse(_ output: String) -> [String: String] {
        var env: [String: String] = [:]
        for entry in output.split(separator: "\0") {
            guard let eq = entry.firstIndex(of: "=") else { continue }
            env[String(entry[..<eq])] = String(entry[entry.index(after: eq)...])
        }
        return env
    }

    public static func keep(_ env: [String: String]) -> [String: String] {
        env.filter { keptNames.contains($0.key) && !$0.value.isEmpty }
    }

    /// Runs `shell -ilc 'env -0'` (on the host inside a Flatpak) and keeps PATH and tool variables.
    /// Gives up after `timeout` (a slow or prompting shell startup) and returns nothing.
    public static func capture(shell: String, flatpak: Bool, environment: [String: String] = [:],
                               timeout: TimeInterval = 10) async -> [String: String] {
        let inv = HostCommand.argv([shell, "-ilc", "env -0"], flatpak: flatpak, environment: environment, user: [:])
        return await withCheckedContinuation { cont in
            Thread.detachNewThread {
                cont.resume(returning: keep(parse(String(decoding: run(inv, timeout: timeout) ?? Data(), as: UTF8.self))))
            }
        }
    }

    /// Runs `inv` with stdin from /dev/null and returns its stdout. Stops at end of output, at the deadline, or
    /// once the shell has exited and output has gone quiet (a background job the shell started may hold the pipe).
    private static func run(_ inv: HostInvocation, timeout: TimeInterval) -> Data? {
        #if os(Linux)
        guard let child = try? PipedSpawn.start(inv, in: AppSettings.realHome, mergeStderr: false) else { return nil }
        let exited = ExitWatch()
        PipedSpawn.onExit(child.pid) { _ in exited.set() }
        // stderr stays open until the end: an interactive shell without a terminal warns there ("no job
        // control"), and writing to a closed pipe would kill it.
        let fd = child.stdout
        let stop = { if !exited.isSet { kill(child.pid, SIGKILL) } }
        let isRunning = { !exited.isSet }
        #else
        let p = Process()
        p.executableURL = URL(fileURLWithPath: inv.executable)
        p.arguments = inv.arguments
        var env = ProcessInfo.processInfo.environment
        env.merge(inv.environment) { $1 }
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let fd = out.fileHandleForReading.fileDescriptor
        let stop = { if p.isRunning { p.terminate() } }
        let isRunning = { p.isRunning }
        #endif
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, 100)
            if ready > 0 {
                let n = read(fd, &buffer, buffer.count)
                if n < 0 && errno == EINTR { continue }
                if n <= 0 { break }
                data.append(contentsOf: buffer[0..<n])
            } else if ready == 0, !isRunning(), data.last == 0 {
                break
            }
        }
        stop()
        #if os(Linux)
        close(fd)
        if let err = child.stderr { close(err) }
        #endif
        return data
    }
}

#if os(Linux)
private final class ExitWatch: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func set() { lock.lock(); done = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return done }
}
#endif
