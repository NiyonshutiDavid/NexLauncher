import SwiftUI
import NexCore

/// "Ask AI" inside a project: a side panel with a composer and this project's runs, so you never leave the page.
struct ProjectAIPanel: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    let project: Project
    @State private var text = ""
    @State private var agent: AgentKind = .claude
    @State private var autonomy: AgentAutonomy = .edit
    @State private var linkedTaskID: UUID?

    private var runs: [AgentRun] { model.agentRuns(for: project) }
    private var canStart: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        // Sized to the measured column so wide content (prompt, pickers) wraps instead of running past the edge.
        GeometryReader { geo in
            panel.frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    composer
                    if runs.isEmpty {
                        emptyRuns
                    } else {
                        Text("RUNS IN THIS PROJECT").font(.caption.weight(.semibold)).foregroundStyle(theme.fg3)
                        ForEach(runs) { run in
                            AgentRunCard(model: model, run: run)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                }
                .padding(16)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .clipped()
        .background(theme.canvas)
        .animation(.spring(duration: 0.4), value: runs.map(\.id))
        .onAppear {
            agent = model.settings.settings.defaultAgent
            autonomy = model.settings.settings.agentAutonomy
            applyDraft()
        }
        .onChange(of: model.agentDraft) { _, _ in applyDraft() }
        .task { await model.agents.refresh() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").font(.system(size: 13, weight: .bold)).foregroundStyle(theme.onAccent)
                .frame(width: 30, height: 30).background(Circle().fill(theme.accent))
            VStack(alignment: .leading, spacing: 1) {
                Text("Ask AI").font(.headline).foregroundStyle(theme.fg)
                Text(project.name).font(.caption).foregroundStyle(theme.fg2).lineLimit(1)
            }
            Spacer()
            Button { model.page = .ai } label: { Image(systemName: "arrow.up.right.square") }
                .buttonStyle(.plain).foregroundStyle(theme.fg2).help("Open the AI page")
            Button { withAnimation { model.aiPanelProjectID = nil } } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(theme.fg2).help("Close")
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Menu {
                ForEach(AgentKind.allCases) { kind in
                    Button { agent = kind } label: {
                        Label(kind.displayName + (model.agents.status(kind).installed ? "" : " (not installed)"), systemImage: kind.symbol)
                    }
                }
            } label: { Label(agent.displayName, systemImage: agent.symbol) }
            .menuStyle(.button).fixedSize()

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("What should \(agent.displayName) do in \(project.name)?")
                        .foregroundStyle(theme.fg3).fixedSize(horizontal: false, vertical: true).padding(.top, 8).padding(.leading, 5)
                }
                TextEditor(text: $text).font(.body).scrollContentBackground(.hidden).frame(minWidth: 0, maxWidth: .infinity, minHeight: 90)
            }
            .padding(8)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.line))

            Picker("", selection: $autonomy) {
                ForEach(AgentAutonomy.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: .infinity)
            Label(autonomy.explanation, systemImage: autonomy == .full ? "exclamationmark.triangle.fill" : "info.circle")
                .font(.caption).foregroundStyle(autonomy == .full ? .orange : theme.fg2)
            if let error = model.agentError { Text(error).font(.callout).foregroundStyle(.red) }
            if linkedTaskID != nil {
                Label("Linked to a task: it's marked done when the agent succeeds", systemImage: "link").font(.caption).foregroundStyle(theme.fg2)
            }
            HStack {
                if agent.binary != nil {
                    Pill("Terminal", style: .quiet, systemImage: "terminal") { model.startAgentInTerminal(agent, task: text, project: project) }
                }
                Spacer()
                Pill(agent == .antigravity ? "Open" : "Start", systemImage: "sparkles") { start() }
                    .opacity(canStart ? 1 : 0.4)
            }
        }
    }

    private var emptyRuns: some View {
        VStack(spacing: 10) {
            IllustrationView(.robot).frame(height: 110)
            Text("Runs you start here stay with this project.").font(.callout).foregroundStyle(theme.fg2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 12)
    }

    private func applyDraft() {
        guard let draft = model.agentDraft, draft.projectID == project.id else { return }
        text = draft.text
        linkedTaskID = draft.taskID
        model.agentDraft = nil
    }

    private func start() {
        guard canStart else { return }
        let linked = model.tasks.first { $0.id == linkedTaskID }
        if model.startAgent(agent, task: text, project: project, linkedTask: linked, autonomy: autonomy) != nil {
            text = ""
            linkedTaskID = nil
        }
    }
}
