import SwiftUI
import AppKit
import NexCore

extension AgentKind {
    var symbol: String {
        switch self {
        case .claude: return "asterisk"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .gemini: return "sparkle"
        case .antigravity: return "atom"
        case .custom: return "terminal"
        }
    }
}

/// AI mode: pick an agent, describe a task in a project, and follow its progress.
struct AIPage: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    @State private var text = ""
    @State private var projectID: String?
    @State private var agent: AgentKind = .claude
    @State private var autonomy: AgentAutonomy = .edit
    @State private var linkedTaskID: UUID?

    private var project: Project? { model.project(id: projectID ?? "") ?? model.projects.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HeroBanner(eyebrow: "AI mode", title: "Your AI assistant",
                           subtitle: "Give Claude Code, Codex, Gemini or Antigravity a task in any project. They work in the project folder and report back here.",
                           illustration: .robot)
                agentsGrid
                composer
                if !model.agentRuns.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader("Runs")
                        ForEach(model.agentRuns) { run in
                            AgentRunCard(model: model, run: run)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.spring(duration: 0.4), value: model.agentRuns.map(\.id))
        .navigationTitle("AI Assistant")
        .onAppear {
            agent = model.settings.settings.defaultAgent
            autonomy = model.settings.settings.agentAutonomy
            applyDraft()
        }
        .onChange(of: model.agentDraft) { _, _ in applyDraft() }
        .task { await model.agents.refresh() }
    }

    private func applyDraft() {
        guard let draft = model.agentDraft else { return }
        text = draft.text
        projectID = draft.projectID
        linkedTaskID = draft.taskID
        model.agentDraft = nil
    }

    // MARK: Agents

    private var agentsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 14)], alignment: .leading, spacing: 14) {
            ForEach(AgentKind.allCases) { kind in
                let status = model.agents.status(kind)
                Button { agent = kind } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: kind.symbol).font(.title3.weight(.semibold)).foregroundStyle(agent == kind ? theme.onAccent : theme.accent)
                                .frame(width: 36, height: 36)
                                .background(agent == kind ? theme.accent : theme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Spacer()
                            if agent == kind { Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent) }
                        }
                        Text(kind.displayName).font(.headline).foregroundStyle(theme.fg)
                        Text(statusLine(kind, status)).font(.caption).foregroundStyle(status.installed ? Color.green : theme.fg3).lineLimit(2)
                        HStack(spacing: 8) {
                            if status.installed, kind.signInCommand != nil {
                                Button("Sign in") { model.signIn(kind) }.buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(theme.accent)
                            }
                            if !status.installed && kind != .custom {
                                Button("Copy install command") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(kind.installHint, forType: .string)
                                }
                                .buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(theme.accent)
                            }
                        }
                    }
                    .padding(16).frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(agent == kind ? theme.accent : theme.line, lineWidth: agent == kind ? 2 : 1))
                }
                .buttonStyle(PressableStyle())
                .hoverLift()
            }
        }
    }

    private func statusLine(_ kind: AgentKind, _ status: AgentStatus) -> String {
        switch kind {
        case .custom:
            return model.settings.settings.customAgentCommand.isEmpty ? "Set its command in Settings → AI" : model.settings.settings.customAgentCommand
        case .antigravity:
            return status.installed ? "App installed · opens the project with your task on the clipboard" : "Not installed"
        default:
            return status.installed ? "Installed · \(status.version ?? "")" : "Not installed"
        }
    }

    // MARK: Composer

    private var composer: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text("New task").font(.headline).foregroundStyle(theme.fg)
                    Spacer()
                    Menu {
                        ForEach(model.projects) { p in Button(p.name) { projectID = p.id } }
                    } label: { Label(project?.name ?? "Choose a project", systemImage: "folder") }
                    .menuStyle(.button).fixedSize()
                }
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Describe what you want done, e.g. \"Add a dark mode toggle to the settings page and write a test for it\"")
                            .foregroundStyle(theme.fg3).padding(.top, 8).padding(.leading, 5)
                    }
                    TextEditor(text: $text).font(.body).scrollContentBackground(.hidden).frame(minHeight: 110)
                }
                .padding(8)
                .background(theme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Picker("Autonomy", selection: $autonomy) {
                    ForEach(AgentAutonomy.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).frame(maxWidth: 380)
                Label(autonomy.explanation, systemImage: autonomy == .full ? "exclamationmark.triangle.fill" : "info.circle")
                    .font(.caption).foregroundStyle(autonomy == .full ? .orange : theme.fg2)
                if let error = model.agentError { Text(error).font(.callout).foregroundStyle(.red) }
                if let message = model.statusMessage { Text(message.text).font(.callout).foregroundStyle(theme.fg2) }
                HStack {
                    if linkedTaskID != nil {
                        Label("Linked to a task: it's marked done when the agent succeeds", systemImage: "link").font(.caption).foregroundStyle(theme.fg2)
                    }
                    Spacer()
                    if agent.binary != nil, let project {
                        Pill("Run in terminal", style: .quiet, systemImage: "terminal") { model.startAgentInTerminal(agent, task: text, project: project) }
                    }
                    Pill(agent == .antigravity ? "Open in Antigravity" : "Start", systemImage: "sparkles") { start() }
                        .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || project == nil ? 0.4 : 1)
                }
            }
            .padding(20)
        }
    }

    private func start() {
        guard let project else { return }
        let linked = model.tasks.first { $0.id == linkedTaskID }
        if model.startAgent(agent, task: text, project: project, linkedTask: linked, autonomy: autonomy) != nil {
            text = ""
            linkedTaskID = nil
        }
    }
}

struct AgentRunCard: View {
    @Bindable var model: AppModel
    @Bindable var run: AgentRun
    @Environment(\.theme) private var theme
    @State private var expanded = false
    @State private var reply = ""

    var body: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: run.agent.symbol).foregroundStyle(theme.onAccent).frame(width: 30, height: 30)
                        .background(theme.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(run.agent.displayName) · \(run.projectName)").font(.callout.weight(.semibold)).foregroundStyle(theme.fg)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(elapsed(now: context.date)).font(.caption).foregroundStyle(theme.fg3)
                        }
                    }
                    Spacer()
                    statusBadge
                }
                // The conversation: your message, then the agent's answer.
                HStack(alignment: .top, spacing: 8) {
                    if run.parentID != nil { Image(systemName: "arrowshape.turn.up.left.fill").font(.caption).foregroundStyle(theme.fg3) }
                    Text(run.task.components(separatedBy: "Follow-up:\n\n").last ?? run.task)
                        .font(.callout).foregroundStyle(theme.onAccent).lineLimit(expanded ? nil : 3)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(visibleEvents.enumerated()), id: \.offset) { _, event in eventRow(event) }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                if !run.isRunning, let answer = run.answer, !answer.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: run.agent.symbol).font(.caption).foregroundStyle(theme.accent).frame(width: 18)
                        Text(answer).font(.callout).foregroundStyle(theme.fg).textSelection(.enabled)
                            .lineLimit(expanded ? nil : 8)
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                HStack(spacing: 10) {
                    if run.events.count > 6 { Button(expanded ? "Show less" : "Show all \(run.events.count) steps") { expanded.toggle() }.buttonStyle(.plain).font(.caption).foregroundStyle(theme.accent) }
                    if let cost = run.costUSD { Text(String(format: "$%.3f", cost)).font(.caption).foregroundStyle(theme.fg3) }
                    Spacer()
                    if run.isRunning {
                        Pill("Stop", style: .destructive) { Task { await model.stopAgent(run) } }
                    } else {
                        Pill("Review changes", style: .quiet, systemImage: "arrow.triangle.branch") {
                            model.page = .project(run.projectID); model.detailTab = .git
                        }
                    }
                }
                if !run.isRunning {
                    HStack(spacing: 8) {
                        TextField("Reply to \(run.agent.displayName)…", text: $reply, axis: .vertical)
                            .textFieldStyle(.plain).lineLimit(1...4)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(theme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .onSubmit(send)
                        Pill("Send", systemImage: "paperplane.fill") { send() }
                            .opacity(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                    }
                }
            }
            .padding(18)
            .animation(.spring(duration: 0.35), value: run.status)
        }
    }

    private func send() {
        guard model.continueAgent(run, message: reply) != nil else { return }
        reply = ""
    }

    private var visibleEvents: [AgentEvent] { expanded ? run.events : Array(run.events.suffix(6)) }

    @ViewBuilder private func eventRow(_ event: AgentEvent) -> some View {
        switch event {
        case .text(let t):
            Text(t).font(.caption).foregroundStyle(theme.fg).lineLimit(expanded ? nil : 3).textSelection(.enabled)
        case .tool(let name, let detail):
            Label(detail.isEmpty ? name : "\(name) · \(detail)", systemImage: toolSymbol(name)).font(.caption.monospaced()).foregroundStyle(theme.accent)
        case .result(let ok, let summary, _):
            Label(summary, systemImage: ok ? "checkmark.seal.fill" : "xmark.octagon.fill").font(.caption.weight(.semibold))
                .foregroundStyle(ok ? Color.green : Color.red).lineLimit(expanded ? nil : 4)
        }
    }

    private func toolSymbol(_ name: String) -> String {
        switch name {
        case "Edit", "Write", "MultiEdit": return "pencil"
        case "Bash": return "terminal"
        case "Read": return "doc.text"
        case "Grep", "Glob": return "magnifyingglass"
        default: return "wrench.and.screwdriver"
        }
    }

    @ViewBuilder private var statusBadge: some View {
        switch run.status {
        case .running: HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Working").font(.caption.weight(.semibold)).foregroundStyle(theme.accent) }
        case .succeeded: Badge(text: "Done", tint: .green)
        case .failed: Badge(text: "Failed", tint: .red)
        case .stopped: Badge(text: "Stopped", tint: theme.fg3)
        }
    }

    private func elapsed(now: Date) -> String {
        let end = run.endedAt ?? now
        let s = Int(end.timeIntervalSince(run.startedAt))
        let text = s < 60 ? "\(s)s" : "\(s / 60)m \(s % 60)s"
        if case .failed(let reason) = run.status { return "\(text) · \(reason)" }
        return text
    }
}
