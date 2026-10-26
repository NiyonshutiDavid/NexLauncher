import Foundation
import AppKit
import NexCore
import NexProcess

extension AppModel {
    /// Starts an agent on `task` inside the project. Returns nil (with `agentError` set) if it can't start.
    @discardableResult
    public func startAgent(_ kind: AgentKind, task: String, project: Project, linkedTask: ProjectTask? = nil,
                           autonomy: AgentAutonomy? = nil, replyingTo parent: AgentRun? = nil) -> AgentRun? {
        let text = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { agentError = "Describe the task first."; return nil }
        if kind == .antigravity { openInAntigravity(project: project, task: text); return nil }
        let level = autonomy ?? settings.settings.agentAutonomy
        guard let command = AgentCommandBuilder.command(kind: kind, autonomy: level, customTemplate: settings.settings.customAgentCommand,
                                                        resumeSessionID: parent?.sessionID) else {
            agentError = "Set the custom agent's command in Settings → AI first."
            return nil
        }
        let run = AgentRun(agent: kind, project: project, task: text, autonomy: level, linkedTaskID: linkedTask?.id,
                           parentID: parent?.id, sessionID: parent?.sessionID)
        do {
            let (pid, fd) = try ProcessSpawner.spawn(command: command, directory: project.root,
                                                     environment: [AgentCommandBuilder.taskVariable: text, "NO_COLOR": "1", "TERM": "dumb"])
            run.pid = pid
            ProcessSpawner.pump(fd: fd, pid: pid,
                                onLines: { lines in Task { @MainActor in run.append(lines) } },
                                onExit: { code in Task { @MainActor [weak self] in self?.agentFinished(run, code: code) } })
        } catch {
            agentError = "Couldn't start \(kind.displayName): \(error.localizedDescription)"
            return nil
        }
        agentError = nil
        agentRuns.insert(run, at: 0)
        return run
    }

    /// Replies to a finished run, continuing the same conversation: Claude Code resumes its session; other
    /// agents get the earlier exchange together with the new message.
    @discardableResult
    public func continueAgent(_ run: AgentRun, message: String) -> AgentRun? {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !run.isRunning, let project = project(id: run.projectID) else { return nil }
        let task = run.agent == .claude && run.sessionID != nil
            ? text
            : AgentCommandBuilder.followUpTask(previousTask: run.task, previousAnswer: run.answer ?? "", message: text)
        return startAgent(run.agent, task: task, project: project, autonomy: run.autonomy, replyingTo: run)
    }

    public var runningAgentCount: Int { agentRuns.filter(\.isRunning).count }

    public func stopAllAgents() async {
        for run in agentRuns where run.isRunning { await stopAgent(run) }
    }

    public func stopAgent(_ run: AgentRun) async {
        guard run.isRunning else { return }
        run.stopRequested = true
        await ProcessSpawner.terminateGroup(run.pid)
    }

    private func agentFinished(_ run: AgentRun, code: Int32) {
        run.endedAt = Date()
        if run.stopRequested {
            run.status = .stopped
        } else if code == 0 && run.reportedSuccess != false {
            run.status = .succeeded
        } else {
            let detail = run.reportedSuccess == false ? (run.summary ?? "") : (run.lastText ?? "")
            run.status = .failed("Exited with code \(code)" + (detail.isEmpty ? "" : ": \(detail)"))
        }
        if run.status == .succeeded, let taskID = run.linkedTaskID, let task = tasks.first(where: { $0.id == taskID }) {
            setTaskDone(task, true)
        }
        if run.status != .stopped {
            post(.agentFinished(project: run.projectName, projectID: run.projectID, agent: run.agent.displayName,
                                success: run.status == .succeeded, summary: run.summary ?? run.lastText ?? ""))
        }
    }

    /// Antigravity has no command-line runner: open the project in the app with the task on the clipboard.
    private func openInAntigravity(project: Project, task: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(task, forType: .string)
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([project.root], withApplicationAt: URL(fileURLWithPath: "/Applications/Antigravity.app"), configuration: config)
        agentError = nil
        statusMessage = StatusMessage(text: "Opened \(project.name) in Antigravity. The task is on your clipboard — paste it into the Agent Manager.", isError: false)
    }

    /// Runs the agent interactively in a terminal tab instead (you see and answer everything).
    public func startAgentInTerminal(_ kind: AgentKind, task: String, project: Project) {
        guard let command = AgentCommandBuilder.interactiveCommand(kind: kind, task: task) else { return }
        let session = terminals.open(at: project.root)
        session.send(command + "\n")
        page = .project(project.id)
        detailTab = .terminal
    }

    /// Opens a terminal running the agent's own sign-in.
    public func signIn(_ kind: AgentKind) {
        guard let command = kind.signInCommand else { return }
        let root = settings.settings.scanRoot
        let session = terminals.open(at: root)
        session.send(command + "\n")
        page = .folder(root.path)
        detailTab = .terminal
    }

    /// "Ask AI" on a task: open the AI page with the task filled in.
    public func draftAgentTask(_ task: ProjectTask, project: Project) {
        agentDraft = AgentDraft(projectID: project.id, text: task.notes.isEmpty ? task.title : "\(task.title)\n\n\(task.notes)", taskID: task.id)
        page = .ai
    }
}
