import Testing
import Foundation
import NexCore
@testable import NexProcess

@Suite struct HostCommandTests {
    let dir = URL(fileURLWithPath: "/tmp/demo")

    @Test func plainShell() {
        let inv = HostCommand.shell("npm run dev", in: dir, environment: [:], flatpak: false, shell: "/bin/bash")
        #expect(inv.executable == "/bin/bash")
        #expect(inv.arguments == ["-lc", "npm run dev"])
    }

    @Test func flatpakNeverSplicesCommand() {
        let command = #"echo "a; rm -rf /""#
        let inv = HostCommand.shell(command, in: dir, environment: ["NEX_TASK": "x"], flatpak: true, shell: "/bin/bash")
        #expect(inv.executable == "/usr/bin/flatpak-spawn")
        #expect(Array(inv.arguments.prefix(2)) == ["--host", "--watch-bus"])
        #expect(inv.arguments.contains("--directory=/tmp/demo"))
        #expect(inv.arguments.contains("--env=NEX_TASK=x"))
        #expect(!inv.arguments.contains { $0.contains("rm -rf") && !$0.hasPrefix("--env=NEX_CMD=") })
        #expect(inv.arguments.contains("--env=NEX_CMD=\(command)"))
        #expect(inv.arguments.last == "/bin/bash")
    }

    @Test func argumentsSurviveSpacesAndUnicode() {
        let inv = HostCommand.shell("ls", in: URL(fileURLWithPath: "/tmp/Café App"), environment: [:], flatpak: true, shell: "/bin/sh")
        #expect(inv.arguments.contains("--directory=/tmp/Café App"))
        let git = HostCommand.exec("git", ["status", "--porcelain"], in: URL(fileURLWithPath: "/tmp/My Repo é"), flatpak: true)
        #expect(git.arguments == ["--host", "--directory=/tmp/My Repo é", "git", "status", "--porcelain"])
    }

    @Test func execOutsideFlatpakFindsToolOnPath() {
        let git = HostCommand.exec("git", ["status"], in: dir, flatpak: false)
        #expect(git.executable == "/usr/bin/env")
        #expect(git.arguments == ["git", "status"])
    }

    @Test func macKeepsZsh() {
        #expect(HostCommand.defaultShell(os: .macOS, loginShell: "/usr/local/bin/fish") == "/bin/zsh")
        #expect(HostCommand.defaultShell(os: .linux, loginShell: "/usr/bin/zsh") == "/usr/bin/zsh")
        #expect(HostCommand.defaultShell(os: .linux, loginShell: "/usr/bin/fish", bashExists: true) == "/bin/bash")
        #expect(HostCommand.defaultShell(os: .linux, loginShell: "/usr/bin/fish", bashExists: false) == "/bin/sh")
    }
}

/// A terminal tab that runs a command (an agent, a sign-in) runs it as part of starting the shell, then stays
/// open in an interactive login shell. The command only travels in NEX_CMD.
@Suite struct TerminalInvocationTests {
    let dir = URL(fileURLWithPath: "/home/alex/Café App")
    let command = "claude 'fix the footer'; echo $HOME"

    @Test func plainTabIsALoginShell() {
        let inv = HostCommand.terminal(shell: "/bin/bash", in: dir, command: nil, flatpak: false, user: [:])
        #expect(inv.executable == "/bin/bash")
        #expect(inv.arguments == ["-l"])
    }

    @Test func commandRunsThenTheShellStays() {
        let inv = HostCommand.terminal(shell: "/bin/bash", in: dir, command: command, flatpak: false, user: [:])
        #expect(inv.executable == "/bin/bash")
        #expect(inv.arguments == ["-lc", #"eval "$NEX_CMD"; exec "$0" -l"#, "/bin/bash"])
        #expect(inv.environment["NEX_CMD"] == command)
    }

    @Test func flatpakRunsOnTheHostWithoutSplicing() {
        let inv = HostCommand.terminal(shell: "/bin/bash", in: dir, command: command, flatpak: true, user: [:])
        #expect(inv.executable == HostCommand.flatpakSpawn)
        #expect(inv.arguments.contains("--directory=\(dir.path)"))
        #expect(inv.arguments.contains("--env=NEX_CMD=\(command)"))
        #expect(inv.arguments.contains("--env=TERM=xterm-256color"))
        #expect(inv.arguments.suffix(3) == ["-lc", #"eval "$NEX_CMD"; exec "$0" -l"#, "/bin/bash"])
        #expect(inv.arguments.filter { $0.contains("claude") }.count == 1)
    }
}

@Suite(.serialized) struct HostPGIDTests {
    @Test func lineIsRecordedAndHidden() {
        let rest = ProcessSpawner.takeHostPGID(from: ["NEXPGID=4242", "VITE ready"], pid: 99_001)
        #expect(rest == ["VITE ready"])
        #expect(ProcessSpawner.hostPGID(for: 99_001) == 4242)
    }

    @Test func stopKillsHostProcessGroup() {
        _ = ProcessSpawner.takeHostPGID(from: ["NEXPGID=4242"], pid: 99_003)
        var recorded: [[String]] = []
        let previous = ProcessSpawner.hostRunner
        ProcessSpawner.hostRunner = { args in recorded.append(args); return 0 }
        defer { ProcessSpawner.hostRunner = previous }
        ProcessSpawner.signalGroup(99_003, SIGTERM)
        #expect(recorded == [["--host", "kill", "-TERM", "--", "-4242"]])
    }
}
