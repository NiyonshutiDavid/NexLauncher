import SwiftUI
import AppKit
import NexCore
import NexApp

/// What the quick panel lists: running projects first, then pinned ones that aren't already running.
public struct QuickPanelSections {
    public static let rowHeight: CGFloat = 58
    public static let headerHeight: CGFloat = 28
    public static let maxListHeight: CGFloat = 430

    public static let maxTasks = 5
    public static let taskRowHeight: CGFloat = 40

    public let running: [Project]
    public let pinned: [Project]
    /// Open tasks, newest first, capped at `maxTasks`.
    public let tasks: [ProjectTask]
    public let moreTasks: Int

    public init(running: [Project], pinned: [Project], tasks: [ProjectTask] = []) {
        self.running = running
        let runningIDs = Set(running.map(\.id))
        self.pinned = pinned.filter { !runningIDs.contains($0.id) }
        let open = tasks.filter { !$0.isDone }.sorted { $0.createdAt > $1.createdAt }
        self.tasks = Array(open.prefix(Self.maxTasks))
        self.moreTasks = max(open.count - Self.maxTasks, 0)
    }

    public var isEmpty: Bool { running.isEmpty && pinned.isEmpty && tasks.isEmpty }

    /// An explicit height: a ScrollView with only a max height collapses to nothing inside a menu bar panel.
    public var listHeight: CGFloat {
        let headers = (running.isEmpty ? 0 : 1) + (pinned.isEmpty ? 0 : 1) + (tasks.isEmpty ? 0 : 1)
        let rows = CGFloat(running.count + pinned.count) * Self.rowHeight + CGFloat(headers) * Self.headerHeight + 16
            + CGFloat(tasks.count) * Self.taskRowHeight + (moreTasks > 0 ? 24 : 0)
        return min(rows, Self.maxListHeight)
    }
}

/// The menu bar panel: only what's running and what's pinned. Everything else lives in the main window.
public struct MenuBarContent: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        let sections = QuickPanelSections(running: model.runningProjects, pinned: model.pinnedProjects, tasks: model.tasks)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ProfileAvatar(settings: model.settings.settings, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.greeting).font(.headline).foregroundStyle(theme.fg).lineLimit(1)
                    Text(model.processes.runningCount > 0 ? "\(model.processes.runningCount) service\(model.processes.runningCount == 1 ? "" : "s") running" : "Nothing running")
                        .font(.caption).foregroundStyle(theme.fg2)
                }
                Spacer()
            }
            .padding(14)
            Divider().overlay(theme.line)

            if sections.isEmpty {
                VStack(spacing: 8) {
                    IllustrationView(.pin).frame(width: 96, height: 96)
                    Text("Nothing running, pinned or to do").font(.callout.weight(.semibold)).foregroundStyle(theme.fg)
                    Text("Pin projects or add tasks in NexLauncher to see them here.")
                        .font(.caption).foregroundStyle(theme.fg2).multilineTextAlignment(.center)
                }
                .padding(20).frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if !sections.running.isEmpty {
                            header("Running")
                            ForEach(sections.running) { QuickRow(model: model, project: $0) }
                        }
                        if !sections.pinned.isEmpty {
                            header("Pinned")
                            ForEach(sections.pinned) { QuickRow(model: model, project: $0) }
                        }
                        if !sections.tasks.isEmpty {
                            header("Tasks")
                            ForEach(sections.tasks) { QuickTaskRow(model: model, task: $0) }
                            if sections.moreTasks > 0 {
                                Button("\(sections.moreTasks) more in NexLauncher") { model.page = .tasks; model.showMainWindow() }
                                    .buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(theme.accent)
                                    .padding(.horizontal, 8).frame(height: 24)
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(height: sections.listHeight)
            }

            Divider().overlay(theme.line)
            HStack {
                Button("Open NexLauncher") { model.showMainWindow() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain).font(.callout.weight(.medium)).foregroundStyle(theme.accent)
            .padding(12)
        }
        .frame(width: 360)
        .background(theme.canvas)
        .task { if model.projects.isEmpty { await model.refresh() } }
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased()).font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(theme.fg3)
            .padding(.horizontal, 6).frame(height: QuickPanelSections.headerHeight, alignment: .bottomLeading)
    }
}

private struct QuickRow: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    let project: Project
    @State private var hovering = false

    var body: some View {
        let running = model.isRunning(project)
        let port = model.runningPorts(for: project).first
        HStack(spacing: 10) {
            IconTile(name: project.name, glyph: ProjectGlyph.symbol(for: project), size: 34)
                .overlay(alignment: .bottomTrailing) { if running { PulsingDot(color: .green, size: 7).offset(x: 2, y: 2) } }
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name).font(.callout.weight(.semibold)).foregroundStyle(theme.fg).lineLimit(1)
                Text(running ? (port.map { "Running · localhost:\($0)" } ?? "Starting…") : ProjectSubtitle.text(for: project))
                    .font(.caption).foregroundStyle(running ? Color.green : theme.fg2).lineLimit(1)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 6)
            if let port {
                Pill("Open", style: .quiet, systemImage: "safari") { NSWorkspace.shared.open(URL(string: "http://localhost:\(port)")!) }
                    .help("Open it in your browser")
            }
            if running {
                Pill("Stop", style: .destructive) { Task { await model.stop(project) } }
            } else {
                Pill("Run", systemImage: "play.fill") { Task { await model.toggleRun(project) } }
            }
        }
        .padding(.horizontal, 8).frame(height: QuickPanelSections.rowHeight - 4)
        .background(hovering ? theme.accentSoft.opacity(0.7) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering = $0 }
    }
}

/// An open task: tick it off right from the menu bar.
private struct QuickTaskRow: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    let task: ProjectTask
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button { withAnimation(.spring(duration: 0.35)) { model.setTaskDone(task, true) } } label: {
                Image(systemName: "circle").font(.title3).foregroundStyle(hovering ? theme.accent : theme.fg3)
            }
            .buttonStyle(PressableStyle()).help("Mark as done")
            VStack(alignment: .leading, spacing: 0) {
                Text(task.title).font(.callout.weight(.medium)).foregroundStyle(theme.fg).lineLimit(1)
                Text(task.projectName).font(.caption2).foregroundStyle(theme.fg3).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).frame(height: QuickPanelSections.taskRowHeight - 2)
        .background(hovering ? theme.accentSoft.opacity(0.7) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering = $0 }
        .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .trailing).combined(with: .opacity)))
    }
}
