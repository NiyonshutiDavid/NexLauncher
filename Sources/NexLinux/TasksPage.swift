import Foundation
import Adwaita
import NexApp
import NexCore

/// Open tasks across projects, with Ask AI and Done (the Mac Tasks page).
struct TasksPage: View {
    let model: AppModel
    @State private var title = ""
    @State private var projectID = ""

    private var open: [ProjectTask] { model.tasks.filter { !$0.isDone } }
    private var done: [ProjectTask] { Array(model.tasks.filter(\.isDone).suffix(10).reversed()) }

    var view: Body {
        ScrollView {
            VStack(spacing: 16) {
                Text(open.count == 1 ? "1 open task" : "\(open.count) open tasks").style("title-1").halign(.start)
                Form {
                    EntryRow("Add a task…", text: $title)
                    ComboRow("Project", selection: $projectID, values: model.projects.map { ChoiceItem(id: $0.id) })
                    ButtonRow().title("Add").activated {
                        guard let project = model.project(id: projectID.isEmpty ? (model.projects.first?.id ?? "") : projectID),
                              !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        _ = model.addTask(title: title, notes: "", project: project)
                        title = ""
                    }
                }
                TaskList(model: model, tasks: open)
                if !done.isEmpty {
                    Text("Recently done").style("heading").halign(.start)
                    TaskList(model: model, tasks: done)
                }
            }
            .padding(24)
            .frame(maxWidth: 900)
        }
        .topToolbar { BreadcrumbHeader(model: model) }
    }
}

/// Tasks with a done switch and Ask AI.
struct TaskList: View {
    let model: AppModel
    let tasks: [ProjectTask]

    var view: Body {
        Form {
            ForEach(tasks) { task in
                ActionRow(task.title)
                    .subtitle(task.projectName + (task.notes.isEmpty ? "" : "  \(task.notes)"))
                    .suffix {
                        HStack(spacing: 6) {
                            if !task.isDone, let project = model.project(id: task.projectID) {
                                Button("Ask AI") { model.draftAgentTask(task, project: project) }.flat()
                            }
                            Toggle("Done", isOn: Binding(get: { task.isDone }, set: { model.setTaskDone(task, $0) }))
                        }
                        .valign(.center)
                    }
            }
        }
    }
}

/// Android emulators and devices Flutter can run on (iOS simulators are Mac-only).
struct DevicesSection: View {
    let model: AppModel
    @State private var loaded = false

    var view: Body {
        VStack(spacing: 8) {
            HStack {
                Text("Devices").style("heading").halign(.start).hexpand()
                Button(icon: .default(icon: .viewRefresh)) { Task { await model.devices.refresh() } }.flat().tooltip("Refresh devices")
            }
            Form {
                ForEach(model.devices.avds.map { ChoiceItem(id: $0) }) { avd in
                    ActionRow(DeviceParsers.displayName(forAVD: avd.id))
                        .subtitle("Android emulator")
                        .suffix { Button("Launch") { model.devices.launch(avd: avd.id) }.pill().valign(.center) }
                }
                ForEach(model.devices.connected) { device in
                    ActionRow(device.name).subtitle("Ready to run")
                }
            }
            if let hint = model.devices.androidHint { Text(hint).wrap(true).style("dim-label").halign(.start) }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            Task { await model.devices.refresh() }
        }
    }
}
