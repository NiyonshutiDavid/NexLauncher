#if os(Linux)
import Foundation
import Glibc

/// Starts a short-lived command with its own output pipes, stdin from /dev/null and every other descriptor
/// closed. On Linux, Foundation's `Process` only reports an exit once every descendant has let go of a socket it
/// inherits, so a child that outlives the command (git's background gc, a credential daemon) hides the exit.
public enum PipedSpawn {
    public struct Child: Sendable {
        public let pid: pid_t
        public let stdout: Int32
        /// nil when stderr goes to the stdout pipe.
        public let stderr: Int32?
    }

    public static func start(_ inv: HostInvocation, in dir: URL, mergeStderr: Bool) throws -> Child {
        var out: [Int32] = [0, 0], err: [Int32] = [0, 0]
        guard pipe2(&out, O_CLOEXEC) == 0 else { throw POSIXError(.EMFILE) }
        if !mergeStderr, pipe2(&err, O_CLOEXEC) != 0 {
            close(out[0]); close(out[1])
            throw POSIXError(.EMFILE)
        }
        var actions = posix_spawn_file_actions_t()
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, out[1], 1)
        posix_spawn_file_actions_adddup2(&actions, mergeStderr ? out[1] : err[1], 2)
        posix_spawn_file_actions_addchdir_np(&actions, dir.path)
        posix_spawn_file_actions_addclosefrom_np(&actions, 3)

        var environment = ProcessInfo.processInfo.environment
        environment.merge(inv.environment) { $1 }
        let argv = ([inv.executable] + inv.arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, inv.executable, &actions, nil, argv, envp)
        close(out[1])
        if !mergeStderr { close(err[1]) }
        guard rc == 0 else {
            close(out[0])
            if !mergeStderr { close(err[0]) }
            throw POSIXError(POSIXErrorCode(rawValue: rc) ?? .ENOENT)
        }
        return Child(pid: pid, stdout: out[0], stderr: mergeStderr ? nil : err[0])
    }

    /// Reaps `pid` on its own thread (not a GCD worker, so many waits can't starve the pool) and reports the
    /// exit status: the exit code, or 128 + the signal number.
    public static func onExit(_ pid: pid_t, _ handler: @escaping @Sendable (Int32) -> Void) {
        Thread.detachNewThread {
            var status: Int32 = 0
            while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
            handler((status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f))
        }
    }
}
#endif
