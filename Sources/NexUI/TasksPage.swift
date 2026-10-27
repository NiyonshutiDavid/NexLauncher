import SwiftUI
import NexCore
import NexApp

/// All tasks across projects.
struct TasksPage: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    private var projectsWithTasks: [Project] {
        model.projects.filter { p in model.tasks.contains { $0.projectID == p.id && !$0.isDone } }
    }
    private var recentlyDone: [ProjectTask] {
        model.tasks.filter(\.isDone).sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }.prefix(10).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                let open = model.openTaskCount
                HeroBanner(eyebrow: "Tasks", title: open == 0 ? "All caught up" : "\(open) open task\(open == 1 ? "" : "s")",
                           subtitle: "Plan what's next for each project. Tick tasks off or hand them to your AI assistant — finished ones appear in the Tasks widget.",
                           illustration: .checklist,
                           actions: [HeroAction(title: "Add the widget", systemImage: "rectangle.3.group", style: .quiet) { model.sheet = .widgetsHowTo }])
                TaskComposer(model: model, fixedProject: nil)
                if projectsWithTasks.isEmpty && recentlyDone.isEmpty {
                    Text("No tasks yet. Add one above — pick the project it belongs to.").foregroundStyle(theme.fg2)
                }
                ForEach(projectsWithTasks) { project in
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(project.name, actionTitle: "Open") { model.page = .project(project.id); model.detailTab = .tasks }
                        TaskList(model: model, tasks: model.tasks(for: project).filter { !$0.isDone }, showProject: false)
                    }
                }
                if !recentlyDone.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("Recently done")
                        TaskList(model: model, tasks: recentlyDone, showProject: true)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fadingHeader(crumbs: [Crumb(title: "Projects", page: .home), Crumb(title: "Tasks", page: nil)],
                      onSelect: { model.page = $0 }, onBack: { model.page = .home })
    }
}

/// A project's tasks (detail page tab).
struct ProjectTasksTab: View {
    @Bindable var model: AppModel
    let project: Project

    var body: some View {
        let all = model.tasks(for: project)
        VStack(alignment: .leading, spacing: 18) {
            TaskComposer(model: model, fixedProject: project)
            TaskList(model: model, tasks: all.filter { !$0.isDone }, showProject: false)
            let done = all.filter(\.isDone)
            if !done.isEmpty {
                SectionHeader("Done")
                TaskList(model: model, tasks: done, showProject: false)
            }
        }
    }
}

struct TaskComposer: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    let fixedProject: Project?
    @State private var title = ""
    @State private var notes = ""
    @State private var projectID: String?

    private var target: Project? { fixedProject ?? model.project(id: projectID ?? "") ?? model.projects.first }

    var body: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(theme.accent).font(.title3)
                    TextField("Add a task…", text: $title).textFieldStyle(.plain).font(.title3)
                        .onSubmit(add)
                    if fixedProject == nil {
                        Menu {
                            ForEach(model.projects) { p in Button(p.name) { projectID = p.id } }
                        } label: { Text(target?.name ?? "Project").font(.callout) }
                        .menuStyle(.button).fixedSize()
                    }
                    Pill("Add") { add() }.opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                }
                TextField("Notes (optional)", text: $notes, axis: .vertical).textFieldStyle(.plain).lineLimit(1...3)
                    .font(.callout).foregroundStyle(theme.fg2).padding(.leading, 32)
            }
            .padding(16)
        }
    }

    private func add() {
        guard let target else { return }
        var added: ProjectTask?
        withAnimation(.spring(duration: 0.4)) { added = model.addTask(title: title, notes: notes, project: target) }
        guard added != nil else { return }
        title = ""
        notes = ""
    }
}

struct TaskList: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    let tasks: [ProjectTask]
    let showProject: Bool

    var body: some View {
        VStack(spacing: 8) {
            ForEach(tasks) { task in
                HStack(alignment: .top, spacing: 12) {
                    Button { withAnimation(.spring(duration: 0.3)) { model.setTaskDone(task, !task.isDone) } } label: {
                        Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.title3).foregroundStyle(task.isDone ? theme.accent : theme.fg3)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title).font(.callout.weight(.medium)).strikethrough(task.isDone)
                            .foregroundStyle(task.isDone ? theme.fg3 : theme.fg)
                        if !task.notes.isEmpty { Text(task.notes).font(.caption).foregroundStyle(theme.fg2) }
                        HStack(spacing: 6) {
                            if showProject { Badge(text: task.projectName, tint: theme.fg2) }
                            if let done = task.doneAt { Text("Done \(done.formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(theme.fg3) }
                        }
                    }
                    Spacer()
                    if !task.isDone, let project = model.project(id: task.projectID) {
                        Pill("Ask AI", style: .quiet, systemImage: "sparkles") { model.draftAgentTask(task, project: project) }
                            .help("Hand this task to your AI assistant")
                    }
                }
                .padding(14)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.line.opacity(0.7)))
                .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                .contextMenu {
                    Button(task.isDone ? "Mark as not done" : "Mark as done") { model.setTaskDone(task, !task.isDone) }
                    Button("Delete", role: .destructive) { model.deleteTask(task) }
                }
            }
        }
    }
}
