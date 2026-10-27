import Foundation
import Adwaita
import NexApp
import NexCore

/// Choose an agent, describe a task, follow its runs (the Mac AI Assistant page).
struct AIPage: View {
    let model: AppModel
    @State private var loaded = false

    var view: Body {
        ScrollView {
            VStack(spacing: 16) {
                Text("Your AI assistant").style("title-1").halign(.start)
                Text("Give Claude Code, Codex, Antigravity or Gemini a task in any project. They work in the project folder and report back here.")
                    .wrap(true).style("dim-label").halign(.start)
                Form {
                    ForEach(AgentKind.allCases.map { ChoiceItem(id: $0.rawValue) }) { item in
                        let kind = AgentKind(rawValue: item.id)!
                        ActionRow(kind.displayName).subtitle(statusLine(kind))
                    }
                }
                AgentComposer(model: model, projectID: nil)
                if !model.agentRuns.isEmpty {
                    Text("Runs").style("heading").halign(.start)
                    ForEach(model.agentRuns) { run in AgentRunRow(model: model, run: run) }
                }
            }
            .padding(24)
            .frame(maxWidth: 900)
        }
        .topToolbar { BreadcrumbHeader(model: model) }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            Task { await model.agents.refresh() }
        }
    }

    private func statusLine(_ kind: AgentKind) -> String {
        let status = model.agents.status(kind)
        if kind == .custom { return model.settings.settings.customAgentCommand.isEmpty ? "Set its command in Settings" : model.settings.settings.customAgentCommand }
        if let notice = kind.notice { return (status.installed ? "Installed. " : "Not installed. ") + notice }
        return status.installed ? "Installed \(status.version ?? "")" : "Not installed: \(kind.installHint)"
    }
}

/// Agent, autonomy and the task; starts a run in the chosen project.
struct AgentComposer: View {
    let model: AppModel
    /// Fixed project (the side panel), or nil to choose one.
    let projectID: String?
    @State private var text = ""
    @State private var agent = AgentKind.claude.rawValue
    @State private var autonomy = AgentAutonomy.edit.rawValue
    @State private var chosenProject = ""
    @State private var primed = false

    private var project: Project? {
        model.project(id: projectID ?? (chosenProject.isEmpty ? model.projects.first?.id ?? "" : chosenProject))
    }

    var view: Body {
        VStack(spacing: 8) {
            Form {
                ComboRow("Agent", selection: $agent, values: AgentKind.allCases.map { ChoiceItem(id: $0.rawValue) })
                ComboRow("May", selection: $autonomy, values: AgentAutonomy.allCases.map { ChoiceItem(id: $0.rawValue) })
                    .subtitle(AgentAutonomy(rawValue: autonomy)?.explanation ?? "")
                if projectID == nil {
                    ComboRow("Project", selection: $chosenProject, values: model.projects.map { ChoiceItem(id: $0.id) })
                }
            }
            TextEditor(text: $text)
                .innerPadding(10)
                .frame(minHeight: 110)
                .style("card")
            if let error = model.agentError { Text(error).wrap(true).style("error").halign(.start) }
            Button("Start") {
                guard let project, let kind = AgentKind(rawValue: agent) else { return }
                let linked = model.tasks.first { $0.id == model.agentDraft?.taskID }
                if model.startAgent(kind, task: text, project: project, linkedTask: linked,
                                    autonomy: AgentAutonomy(rawValue: autonomy)) != nil { text = "" }
            }
            .suggested().pill().halign(.end)
        }
        .onAppear {
            if !primed {
                primed = true
                agent = model.settings.settings.defaultAgent.rawValue
                autonomy = model.settings.settings.agentAutonomy.rawValue
            }
            if let draft = model.agentDraft, projectID == nil || draft.projectID == projectID {
                text = draft.text
                chosenProject = draft.projectID
            }
        }
    }
}

/// One run: what the agent did, its answer, Stop, and a reply box that continues the conversation.
struct AgentRunRow: View {
    let model: AppModel
    let run: AgentRun
    @State private var reply = ""

    private var statusText: String {
        switch run.status {
        case .running: return "Working…"
        case .succeeded: return "Done"
        case .failed(let message): return "Failed: \(message)"
        case .stopped: return "Stopped"
        }
    }

    var view: Body {
        VStack(spacing: 6) {
            HStack {
                Text("\(run.agent.displayName) · \(run.projectName)").style("heading").halign(.start).hexpand()
                Text(statusText).style("dim-label")
                if run.isRunning { Button("Stop") { Task { await model.stopAgent(run) } }.destructive().pill() }
            }
            Text(run.task).wrap(true).halign(.start)
            Text(events).wrap(true).selectable(true).style("monospace").style("dim-label").halign(.start)
            if let answer = run.answer { Text(answer).wrap(true).selectable(true).halign(.start) }
            if !run.isRunning {
                Form {
                    EntryRow("Reply", text: $reply)
                        .suffix {
                            Button("Send") {
                                if model.continueAgent(run, message: reply) != nil { reply = "" }
                            }
                            .flat().valign(.center)
                        }
                }
            }
        }
        .padding(14)
        .style("card")
    }

    private var events: String {
        run.events.suffix(8).map { event in
            switch event {
            case .text(let text): return text
            case .tool(let name, let detail): return "\(name) \(detail)"
            case .result(_, let summary, _): return summary
            }
        }.joined(separator: "\n")
    }
}

/// "Ask AI" beside a project.
struct ProjectAIPanel: View {
    let model: AppModel
    let project: Project

    var view: Body {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Text("Ask AI").style("title-3").halign(.start).hexpand()
                    Button(icon: .custom(name: "window-close-symbolic")) { model.aiPanelProjectID = nil }.flat().tooltip("Close")
                }
                Text(project.name).style("dim-label").halign(.start)
                AgentComposer(model: model, projectID: project.id)
                ForEach(model.agentRuns(for: project)) { run in AgentRunRow(model: model, run: run) }
            }
            .padding(16)
        }
        .frame(minWidth: 340)
    }
}
