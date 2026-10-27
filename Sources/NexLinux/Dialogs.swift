import Foundation
import Adwaita
import NexApp
import NexCore

/// Missing dependencies: confirm, then show each install step's progress (the Mac setup sheet).
struct SetupDialogContent: View {
    let model: AppModel

    var view: Body {
        VStack(spacing: 12) {
            if let setup = model.setup {
                Text("Set up \(setup.project.name)").style("title-2").halign(.start)
                Text("Some dependencies are missing. NexLauncher will install them with the project's own tools, then run it.")
                    .wrap(true).halign(.start)
                Form {
                    ForEach(setup.steps.map { ChoiceItem(id: $0.title) }) { item in
                        let step = setup.steps.first { $0.title == item.id }!
                        ActionRow(step.title).subtitle(statusText(step.status) + "  " + step.command)
                    }
                }
                if let line = model.setupLastLine { Text(line).ellipsize().style("monospace").style("dim-label").halign(.start) }
                if case .failed(let message) = setup.phase { Text(message).wrap(true).style("error").halign(.start) }
                HStack(spacing: 8) {
                    Button("Cancel") { model.cancelInstall() }.pill()
                    if setup.phase == .confirm {
                        Button("Install and run") { Task { await model.confirmInstall() } }.suggested().pill()
                    }
                }
                .halign(.end)
            }
        }
        .padding(20)
    }

    private func statusText(_ status: SetupStep.Status) -> String {
        switch status {
        case .pending: return "Waiting"
        case .running: return "Installing…"
        case .done: return "Done"
        case .failed: return "Failed"
        }
    }
}

/// New folder or clone a repository (the Mac "Add project" pop-up), using the shared form logic.
struct AddProjectDialogContent: View {
    let model: AppModel
    @State private var mode: AddProjectMode
    @State private var newFolder = NewFolderForm()
    @State private var clone = CloneForm()
    @State private var busy = false
    @State private var progress = ""
    @State private var error: String?

    init(model: AppModel, mode: AddProjectMode) {
        self.model = model
        self._mode = State(wrappedValue: mode)
    }

    private var parent: URL { model.settings.settings.scanRoot }

    var view: Body {
        VStack(spacing: 12) {
            Text("Add project").style("title-2").halign(.start)
            ToggleGroup(selection: Binding(get: { mode == .newFolder ? "New folder" : "Clone repository" },
                                           set: { mode = $0 == "New folder" ? .newFolder : .clone }),
                        values: ["New folder", "Clone repository"], id: \.self, label: \.self)
            if mode == .newFolder {
                Form {
                    EntryRow("Project name", text: Binding(get: { newFolder.name }, set: { newFolder.name = $0 }))
                    SwitchRow("Initialise a git repository", isOn: Binding(get: { newFolder.initGit }, set: { newFolder.initGit = $0 }))
                }
                if let problem = newFolder.problem(in: parent) { Text(problem).style("error").halign(.start) }
            } else {
                Form {
                    EntryRow("Repository URL", text: Binding(get: { clone.url }, set: { clone.setURL($0) }))
                    EntryRow("Folder name", text: Binding(get: { clone.name }, set: { clone.setName($0) }))
                }
                if let problem = clone.problem(in: parent) { Text(problem).style("error").halign(.start) }
                if busy { Text(progress).ellipsize().style("monospace").style("dim-label").halign(.start) }
            }
            if let error { Text(error).wrap(true).style("error").halign(.start) }
            Text("In \(parent.path)").style("dim-label").halign(.start)
            HStack(spacing: 8) {
                Button("Cancel") { model.sheet = nil }.pill()
                Button(mode == .newFolder ? "Create" : "Clone") { submit() }
                    .suggested().pill()
            }
            .halign(.end)
        }
        .padding(20)
    }

    private func submit() {
        let canSubmit = mode == .newFolder ? newFolder.canSubmit(in: parent) : clone.canSubmit(in: parent)
        guard canSubmit, !busy else { return }
        busy = true
        error = nil
        Task {
            do {
                if mode == .newFolder {
                    _ = try await model.createProject(name: newFolder.name, in: parent, initGit: newFolder.initGit)
                } else {
                    _ = try await model.cloneProject(url: clone.url, name: clone.name, in: parent) { line in
                        Task { @MainActor in progress = line }
                    }
                }
                model.sheet = nil
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
