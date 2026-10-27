import Foundation
import NexCore

/// A program to start: what to run, its arguments, and environment to add.
public struct HostInvocation: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]
}

/// Builds how a command reaches the user's system. Inside a Flatpak, tools live on the host, so everything goes
/// through `flatpak-spawn --host`; the command itself only ever travels in the `NEX_CMD` environment variable.
public enum HostCommand {
    static let flatpakSpawn = "/usr/bin/flatpak-spawn"

    /// Runs `command` in a login shell. In Flatpak, the host shell prints `NEXPGID=<n>` (its process group) first.
    public static func shell(_ command: String, in directory: URL, environment: [String: String], flatpak: Bool, shell: String) -> HostInvocation {
        guard flatpak else { return HostInvocation(executable: shell, arguments: ["-lc", command], environment: environment) }
        var args = ["--host", "--watch-bus", "--directory=\(directory.path)", "--env=NEX_CMD=\(command)"]
        args += environment.sorted { $0.key < $1.key }.map { "--env=\($0.key)=\($0.value)" }
        // $0 is the login shell; the script only refers to variables, never to the command text.
        args += ["/bin/sh", "-c", #"echo "NEXPGID=$$"; exec setsid -w "$0" -lc "$NEX_CMD""#, shell]
        return HostInvocation(executable: flatpakSpawn, arguments: args, environment: [:])
    }

    /// Runs a tool found on PATH with an argument array (no shell).
    public static func exec(_ tool: String, _ arguments: [String], in directory: URL, flatpak: Bool) -> HostInvocation {
        if flatpak {
            return HostInvocation(executable: flatpakSpawn, arguments: ["--host", "--directory=\(directory.path)", tool] + arguments, environment: [:])
        }
        return HostInvocation(executable: "/usr/bin/env", arguments: [tool] + arguments, environment: [:])
    }

    /// The shell services run in. macOS keeps `/bin/zsh` as it always has; Linux uses the login shell when it
    /// understands POSIX syntax (the commands NexLauncher builds are POSIX), else bash, else `/bin/sh`.
    public static func defaultShell(os: HostOS, loginShell: String, bashExists: Bool = FileManager.default.fileExists(atPath: "/bin/bash")) -> String {
        guard os == .linux else { return "/bin/zsh" }
        let posix: Set<String> = ["sh", "bash", "zsh", "dash", "ksh", "mksh", "ash", "yash"]
        if posix.contains(URL(fileURLWithPath: loginShell).lastPathComponent) { return loginShell }
        return bashExists ? "/bin/bash" : "/bin/sh"
    }

    public static var defaultShell: String { defaultShell(os: .current, loginShell: Platform.loginShell) }

    /// The service shell invocation for this system.
    public static func service(_ command: String, in directory: URL, environment: [String: String]) -> HostInvocation {
        shell(command, in: directory, environment: environment, flatpak: Platform.isFlatpak, shell: defaultShell)
    }
}
