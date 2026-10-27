import Foundation

/// A program to start: what to run, its arguments, and environment to add.
public struct HostInvocation: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]
}

/// Builds how a command reaches the user's system. Inside a Flatpak, tools live on the host, so everything goes
/// through `flatpak-spawn --host`; the command itself only ever travels in the `NEX_CMD` environment variable.
public enum HostCommand {
    public static let flatpakSpawn = "/usr/bin/flatpak-spawn"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var captured: [String: String] = [:]
    /// The login shell's PATH and tool variables (see `ShellEnvironment`), added to every host command.
    public static var userEnvironment: [String: String] { lock.lock(); defer { lock.unlock() }; return captured }
    public static func setUserEnvironment(_ env: [String: String]) { lock.lock(); captured = env; lock.unlock() }

    /// Runs `command` in a login shell. In Flatpak, the host shell prints `NEXPGID=<n>` (its process group) first.
    public static func shell(_ command: String, in directory: URL, environment: [String: String], flatpak: Bool, shell: String,
                             user: [String: String] = userEnvironment) -> HostInvocation {
        let environment = user.merging(environment) { $1 }
        guard flatpak else { return HostInvocation(executable: shell, arguments: ["-lc", command], environment: environment) }
        var args = ["--host", "--watch-bus", "--directory=\(directory.path)", "--env=NEX_CMD=\(command)"]
        args += environment.sorted { $0.key < $1.key }.map { "--env=\($0.key)=\($0.value)" }
        // $0 is the login shell; the script only refers to variables, never to the command text. flatpak-spawn
        // already makes this sh a group leader, so setsid forks: the group id is printed from inside the new
        // session, where the service runs.
        args += ["/bin/sh", "-c", #"exec setsid -w /bin/sh -c 'echo "NEXPGID=$$"; exec "$0" -lc "$NEX_CMD"' "$0""#, shell]
        return HostInvocation(executable: flatpakSpawn, arguments: args, environment: [:])
    }

    /// Runs a tool found on PATH with an argument array (no shell). Outside Flatpak the environment is the
    /// caller's to set on the process; inside, it has to travel as `--env` arguments.
    public static func exec(_ tool: String, _ arguments: [String], in directory: URL,
                            environment: [String: String] = [:], flatpak: Bool,
                            user: [String: String] = userEnvironment) -> HostInvocation {
        let environment = user.merging(environment) { $1 }
        if flatpak {
            let env = environment.sorted { $0.key < $1.key }.map { "--env=\($0.key)=\($0.value)" }
            return HostInvocation(executable: flatpakSpawn, arguments: ["--host", "--directory=\(directory.path)"] + env + [tool] + arguments,
                                  environment: [:])
        }
        return HostInvocation(executable: "/usr/bin/env", arguments: [tool] + arguments, environment: environment)
    }

    /// Runs an exact argument list (`args[0]` is the program): directly, or on the host inside a Flatpak.
    public static func argv(_ args: [String], flatpak: Bool, environment: [String: String] = [:],
                            user: [String: String] = userEnvironment) -> HostInvocation {
        let environment = user.merging(environment) { $1 }
        if flatpak {
            let env = environment.sorted { $0.key < $1.key }.map { "--env=\($0.key)=\($0.value)" }
            return HostInvocation(executable: flatpakSpawn, arguments: ["--host"] + env + args, environment: [:])
        }
        return HostInvocation(executable: args[0], arguments: Array(args.dropFirst()), environment: environment)
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
