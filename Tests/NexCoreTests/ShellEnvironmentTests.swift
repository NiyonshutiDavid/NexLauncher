import Testing
import Foundation
@testable import NexCore

@Suite struct ShellEnvironmentTests {
    @Test func keepsPathAndToolManagersOnly() {
        let env = ShellEnvironment.parse("PATH=/a:/b\0NVM_DIR=/h/.nvm\0PS1=$ \0PWD=/x\0PYENV_ROOT=/h/.pyenv\0WEIRD\0")
        #expect(ShellEnvironment.keep(env) == ["PATH": "/a:/b", "NVM_DIR": "/h/.nvm", "PYENV_ROOT": "/h/.pyenv"])
    }

    /// Ubuntu's stock ~/.bashrc returns early unless the shell is interactive; nvm and friends add themselves
    /// after that line, so their PATH only shows up in an interactive login shell.
    @Test func capturesPathSetAfterTheInteractiveGuard() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try #"[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc""#.write(to: home.appendingPathComponent(".profile"), atomically: true, encoding: .utf8)
        try """
        case $- in *i*) ;; *) return;; esac
        export PATH="$HOME/.nvm/bin:$PATH"
        export NVM_DIR="$HOME/.nvm"
        """.write(to: home.appendingPathComponent(".bashrc"), atomically: true, encoding: .utf8)
        let env = await ShellEnvironment.capture(shell: "/bin/bash", flatpak: false, environment: ["HOME": home.path])
        #expect(env["PATH"]?.hasPrefix(home.path + "/.nvm/bin:") == true)
        #expect(env["NVM_DIR"] == home.path + "/.nvm")
    }

    @Test func hostCommandsCarryTheCapturedEnvironment() {
        let user = ["PATH": "/h/.nvm/bin:/usr/bin"]
        let dir = URL(fileURLWithPath: "/p")
        #expect(HostCommand.shell("npm run dev", in: dir, environment: [:], flatpak: false, shell: "/bin/bash", user: user).environment["PATH"] == "/h/.nvm/bin:/usr/bin")
        #expect(HostCommand.shell("npm run dev", in: dir, environment: [:], flatpak: true, shell: "/bin/bash", user: user).arguments.contains("--env=PATH=/h/.nvm/bin:/usr/bin"))
        #expect(HostCommand.exec("git", ["status"], in: dir, flatpak: false, user: user).environment["PATH"] == "/h/.nvm/bin:/usr/bin")
        #expect(HostCommand.argv(["/bin/bash", "-lc", "x"], flatpak: true, user: user).arguments.contains("--env=PATH=/h/.nvm/bin:/usr/bin"))
        // A caller's own variables win over the captured ones.
        #expect(HostCommand.exec("git", [], in: dir, environment: ["PATH": "/mine"], flatpak: false, user: user).environment["PATH"] == "/mine")
    }
}
