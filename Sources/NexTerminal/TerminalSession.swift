import AppKit
import Foundation
import Observation
import SwiftTerm

/// One terminal tab: a real PTY running the user's login zsh in a chosen folder.
@MainActor @Observable
public final class TerminalSession: NSObject, Identifiable, LocalProcessTerminalViewDelegate {
    public nonisolated let id = UUID()
    public let directory: URL
    public var title: String
    public private(set) var isAlive = false

    let view: LocalProcessTerminalView
    private var started = false

    public init(directory: URL) {
        self.directory = directory
        self.title = directory.lastPathComponent
        self.view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 1200, height: 420))
        super.init()
        view.processDelegate = self
    }

    // MARK: - Lifecycle

    public func start() {
        guard !started else { return }
        started = true
        view.startProcess(executable: "/bin/zsh", args: ["-l"], environment: nil, execName: nil, currentDirectory: directory.path)
        isAlive = view.process?.running ?? false
    }

    public func send(_ text: String) {
        view.send(data: Array(text.utf8)[...])
    }

    public func terminate() {
        guard started else { return }
        let pid = shellPID
        view.terminate()
        if pid > 0 { killpg(pid, SIGHUP); kill(pid, SIGHUP) }     // make sure the shell and its jobs hang up
        isAlive = false
    }

    // MARK: - State

    public var shellPID: pid_t { view.process?.shellPid ?? 0 }

    /// True while something other than the shell itself owns the terminal (a build, a dev server, vim…).
    public var hasForegroundProgram: Bool {
        guard isAlive, let process = view.process else { return false }
        let fd = process.childfd
        guard fd >= 0 else { return false }
        let foreground = tcgetpgrp(fd)
        return foreground > 0 && foreground != process.shellPid
    }

    public var outputForTesting: String {
        String(data: view.getBufferAsData(), encoding: .utf8) ?? ""
    }

    // MARK: - LocalProcessTerminalViewDelegate

    public nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    public nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor in if !title.isEmpty { self.title = title } }
    }

    public nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    public nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in self.isAlive = false }
    }
}
