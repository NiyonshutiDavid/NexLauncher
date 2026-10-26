import Testing
import Foundation
import NexCore
@testable import NexUI

@MainActor
@Suite(.serialized) struct AgentRunTests {
    private func waitUntil(_ timeout: TimeInterval = 15, _ cond: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if cond() { return true }; try? await Task.sleep(for: .milliseconds(25)) }
        return cond()
    }

    private func setup(_ template: String) async -> (Sandbox, AppModel, Project) {
        let sb = Sandbox()
        sb.write("Site/package.json", Sandbox.vite)
        let m = sb.makeModel(); m.reloadWidgets = {}
        m.settings.settings.customAgentCommand = template
        await m.refresh()
        return (sb, m, m.projects[0])
    }

    @Test func aCustomAgentReceivesTheTaskLiterallyAndSucceeds() async {
        let (sb, m, p) = await setup(#"printf 'TASK=[%s]\n' "$NEX_TASK"; pwd"#); defer { _ = sb }
        let evil = #"say "hi"; rm -rf ~/nope; echo $(whoami) `id`"#
        let run = m.startAgent(.custom, task: evil, project: p)
        #expect(run != nil)
        #expect(await waitUntil { run?.status == .succeeded })
        let text = run!.events.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined(separator: "\n")
        #expect(text.contains("TASK=[\(evil)]"))                                // passed through untouched
        #expect(text.contains(p.root.lastPathComponent))                         // ran inside the project
    }

    @Test func aFailingAgentIsReportedWithItsOutput() async {
        let (sb, m, p) = await setup(#": \"$NEX_TASK\"; echo cannot reach model; exit 4"#); defer { _ = sb }
        let run = m.startAgent(.custom, task: "x", project: p)!
        #expect(await waitUntil { if case .failed = run.status { return true } else { return false } })
        guard case .failed(let reason) = run.status else { return }
        #expect(reason.contains("4") && reason.contains("cannot reach model"))
    }

    @Test func stoppingEndsTheRun() async {
        let (sb, m, p) = await setup(#": \"$NEX_TASK\"; echo working; sleep 30"#); defer { _ = sb }
        let run = m.startAgent(.custom, task: "x", project: p)!
        #expect(await waitUntil { run.events.contains(.text("working")) })
        await m.stopAgent(run)
        #expect(await waitUntil { run.status == .stopped })
    }

    @Test func aSuccessfulRunCompletesItsLinkedTaskAndNotifies() async {
        let (sb, m, p) = await setup("echo ok"); defer { _ = sb }
        m.settings.settings.notificationsEnabled = true
        let task = m.addTask(title: "Add a footer", notes: "", project: p)!
        let run = m.startAgent(.custom, task: task.title, project: p, linkedTask: task)!
        #expect(await waitUntil { run.status == .succeeded })
        #expect(await waitUntil { m.tasks.first?.isDone == true })
        #expect(await waitUntil { sb.notifier.posted.contains { $0.title.contains("finished") } })
    }

    @Test func missingCustomCommandCannotStart() async {
        let (sb, m, p) = await setup(""); defer { _ = sb }
        #expect(m.startAgent(.custom, task: "x", project: p) == nil)
        #expect(m.agentError != nil)
    }

    @Test func blankTasksAreRejected() async {
        let (sb, m, p) = await setup("echo ok"); defer { _ = sb }
        #expect(m.startAgent(.custom, task: "   ", project: p) == nil)
    }

    @Test func askingAIForATaskPreparesTheComposer() async {
        let (sb, m, p) = await setup("echo ok"); defer { _ = sb }
        let task = m.addTask(title: "Write tests", notes: "for the API", project: p)!
        m.draftAgentTask(task, project: p)
        #expect(m.page == .ai)
        #expect(m.agentDraft?.projectID == p.id && m.agentDraft?.text == "Write tests\n\nfor the API" && m.agentDraft?.taskID == task.id)
    }

    @Test func agentsAreDetectedThroughTheLoginShell() async {
        let shell = FakeDeviceShell()
        shell.outputs["/bin/zsh -lc command -v claude >/dev/null && claude --version"] = "2.1.300 (Claude Code)\n"
        let catalog = AgentCatalog(shell: shell, antigravityApp: URL(fileURLWithPath: "/nonexistent/Antigravity.app"))
        await catalog.refresh()
        #expect(catalog.status(.claude).installed && catalog.status(.claude).version == "2.1.300 (Claude Code)")
        #expect(!catalog.status(.codex).installed)
        #expect(!catalog.status(.antigravity).installed)
    }
}
