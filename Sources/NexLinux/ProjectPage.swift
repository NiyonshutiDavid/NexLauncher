import Foundation
import Adwaita
import NexApp
import NexCore
import NexProcess

/// A project's page: header with Run, then Overview, Tasks, Terminal, Logs, Git and Files, as on the Mac.
struct ProjectPage: View {
    let model: AppModel
    let project: Project

    private var actions: [RunAction] { model.availableActions(for: project) }
    private var running: Bool { model.isRunning(project) }

    var view: Body {
        OverlaySplitView(visible: Binding(get: { model.aiPanelProjectID == project.id },
                                          set: { if !$0 { model.aiPanelProjectID = nil } })) {
            ProjectAIPanel(model: model, project: project)
        } content: {
            page
        }
        .trailingSidebar()
        .topToolbar { BreadcrumbHeader(model: model) }
    }

    private var page: AnyView {
        ScrollView {
            VStack(spacing: 16) {
                header
                ToggleGroup(selection: Binding(get: { model.detailTab }, set: { model.detailTab = $0 }),
                            values: DetailTab.allCases, id: \.self, label: \.rawValue)
                    .halign(.start)
                tab
            }
            .padding(24)
            .frame(maxWidth: 1100)
        }
    }

    private var header: AnyView {
        VStack(spacing: 8) {
            Text(project.name).style("title-1").halign(.start)
            Text(ProjectSubtitle.text(for: project)).style("dim-label").halign(.start)
            HStack(spacing: 6) {
                if running {
                    Button("Stop") { Task { await model.stop(project) } }.destructive().pill()
                } else {
                    ForEach(actions.map { ChoiceItem(id: $0.rawValue) }) { item in
                        Button(item.id == RunAction.both.rawValue ? "Run Both" : "Run \(item.id)") {
                            if let action = RunAction(rawValue: item.id) { Task { await model.run(project, kinds: action.kinds) } }
                        }
                        .pill()
                    }
                }
                Button(icon: .custom(name: model.isPinned(project) ? "starred-symbolic" : "non-starred-symbolic")) { model.togglePin(project) }
                    .flat().tooltip(model.isPinned(project) ? "Unpin" : "Pin")
                Button(icon: .custom(name: "utilities-terminal-symbolic")) { model.showTerminal(at: project.root, page: model.page) }
                    .flat().tooltip("Open a terminal here")
                Button(icon: .custom(name: "folder-open-symbolic")) { model.services.open(project.root) }
                    .flat().tooltip("Open the folder")
                Button(model.aiPanelProjectID == project.id ? "Hide AI" : "Ask AI") { model.toggleAIPanel(for: project) }
                    .flat()
            }
            .halign(.start)
        }
    }

    private var tab: AnyView {
        switch model.detailTab {
        case .overview: return OverviewTab(model: model, project: project)
        case .logs: return LogsTab(model: model, project: project)
        case .files: return FilesTab(model: model, folder: project.root)
        case .tasks: return TaskList(model: model, tasks: model.tasks(for: project))
        case .git: return GitPanel(model: model, repo: model.git.findRepos(under: project.root).first ?? project.root)
        case .terminal: return TerminalTab(model: model, directory: project.root)
        }
    }
}

struct PlaceholderTab: View {
    let text: String
    var view: Body { Text(text).style("dim-label").padding(24) }
}

/// What's inside: each runnable part with its folder and live state.
struct OverviewTab: View {
    let model: AppModel
    let project: Project

    var view: Body {
        Form {
            ForEach(project.targets.map { ChoiceItem(id: $0.directory.path + "|" + $0.kind.rawValue) }) { item in
                let target = project.targets.first { $0.directory.path + "|" + $0.kind.rawValue == item.id }!
                ActionRow(target.framework ?? target.kind.rawValue.capitalized)
                    .subtitle(stateText(target) + "  " + relative(target.directory))
            }
        }
    }

    private func relative(_ url: URL) -> String {
        let rel = url.path.replacingOccurrences(of: project.root.path, with: "")
        return rel.isEmpty ? "/" : rel
    }

    private func stateText(_ target: ServiceTarget) -> String {
        switch model.processes.states[ProcessManager.id(for: target, projectID: project.id)] ?? .stopped {
        case .stopped: return target.kind.rawValue.capitalized
        case .starting: return "Starting…"
        case .running(let port?): return "Running on port \(port)"
        case .running: return "Running"
        case .failed(let message): return message
        }
    }
}

/// Live output of each service.
struct LogsTab: View {
    let model: AppModel
    let project: Project

    var view: Body {
        VStack(spacing: 12) {
            ForEach(project.targets.map { ChoiceItem(id: $0.directory.path + "|" + $0.kind.rawValue) }) { item in
                let target = project.targets.first { $0.directory.path + "|" + $0.kind.rawValue == item.id }!
                let lines = model.processes.logs[ProcessManager.id(for: target, projectID: project.id)] ?? []
                VStack(spacing: 4) {
                    Text(target.kind.rawValue.capitalized).style("heading").halign(.start)
                    Text(lines.isEmpty ? "No output yet." : lines.suffix(200).joined(separator: "\n"))
                        .selectable(true).wrap(true).style("monospace").halign(.start)
                }
                .padding(12)
                .style("card")
            }
        }
    }
}

/// The folder's files; open one with its default app.
struct FilesTab: View {
    let model: AppModel
    let folder: URL

    private var entries: [ChoiceItem] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { !$0.hasPrefix(".") }.sorted().prefix(200).map { ChoiceItem(id: $0) }
    }

    var view: Body {
        Form {
            ForEach(entries) { entry in
                ActionRow(entry.id)
                    .suffix { Button(icon: .custom(name: "document-open-symbolic")) { model.services.open(folder.appendingPathComponent(entry.id)) }.flat().valign(.center) }
            }
        }
    }
}
