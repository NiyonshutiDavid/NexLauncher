import SwiftUI
import AppKit
import NexCore
import NexApp
import NexGit

struct AddProjectSheet: View {
    @Bindable var model: AppModel
    @Environment(\.closeModal) private var dismiss
    @Environment(\.theme) private var theme
    @State private var mode: AddProjectMode
    @State private var folderForm = NewFolderForm()
    @State private var cloneForm = CloneForm()
    @State private var parent: URL
    @State private var busy = false
    @State private var lastLine = ""
    @State private var errorText: String?
    @State private var task: Task<Void, Never>?

    init(model: AppModel, initialMode: AddProjectMode) {
        self.model = model
        _mode = State(initialValue: initialMode)
        _parent = State(initialValue: model.settings.settings.scanRoot)
    }

    private var problem: String? { mode == .newFolder ? folderForm.problem(in: parent) : cloneForm.problem(in: parent) }
    private var canSubmit: Bool { !busy && (mode == .newFolder ? folderForm.canSubmit(in: parent) : cloneForm.canSubmit(in: parent)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                IllustrationView(mode == .newFolder ? .rocket : .branchGraph).frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add project").font(.title.weight(.bold)).foregroundStyle(theme.fg)
                    Text("Create a folder or clone a repository.").foregroundStyle(theme.fg2)
                }
            }

            Picker("", selection: $mode) {
                Text("New folder").tag(AddProjectMode.newFolder)
                Text("Clone repository").tag(AddProjectMode.clone)
            }
            .pickerStyle(.segmented).labelsHidden().disabled(busy)

            if mode == .newFolder {
                TextField("Project name", text: $folderForm.name).textFieldStyle(.roundedBorder).disabled(busy)
                Toggle("Initialise a git repository (branch “\(model.settings.settings.defaultBranch)”)", isOn: $folderForm.initGit).disabled(busy)
            } else {
                TextField("Repository URL (https, ssh or git@host:owner/repo)", text: Binding(get: { cloneForm.url }, set: { cloneForm.setURL($0) }))
                    .textFieldStyle(.roundedBorder).disabled(busy)
                TextField("Folder name", text: Binding(get: { cloneForm.name }, set: { cloneForm.setName($0) }))
                    .textFieldStyle(.roundedBorder).disabled(busy)
            }

            HStack {
                Image(systemName: "folder").foregroundStyle(theme.fg3)
                Text(parent.path).lineLimit(1).truncationMode(.middle).foregroundStyle(theme.fg2)
                Spacer()
                Button("Choose…") { chooseParent() }.disabled(busy)
            }
            .font(.callout)

            if let message = errorText ?? problem {
                Label(message, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(errorText != nil ? .red : theme.accent)
            }
            if busy {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(lastLine.isEmpty ? "Working…" : lastLine).font(.caption.monospaced()).foregroundStyle(theme.fg2).lineLimit(1)
                }
            }

            HStack {
                Spacer()
                Button(busy ? "Cancel clone" : "Cancel") {
                    if busy { task?.cancel() } else { dismiss() }
                }
                .keyboardShortcut(.cancelAction)
                Pill(mode == .newFolder ? "Create" : "Clone", systemImage: nil) { submit() }
                    .opacity(canSubmit ? 1 : 0.4).disabled(!canSubmit)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 520)
        .background(theme.canvas)
    }

    private func chooseParent() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = parent
        if panel.runModal() == .OK, let url = panel.url { parent = url }
    }

    private func submit() {
        errorText = nil
        busy = true
        lastLine = ""
        let currentParent = parent
        task = Task {
            do {
                switch mode {
                case .newFolder:
                    try await model.createProject(name: folderForm.name, in: currentParent, initGit: folderForm.initGit)
                case .clone:
                    try await model.cloneProject(url: cloneForm.url, name: cloneForm.name, in: currentParent) { line in
                        Task { @MainActor in lastLine = line }
                    }
                }
                dismiss()
            } catch is CancellationError {
                errorText = "Clone cancelled."
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            busy = false
        }
    }
}

struct WidgetsHowToSheet: View {
    @Bindable var model: AppModel
    @Environment(\.closeModal) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 16) {
            IllustrationView(.widgets).frame(width: 130, height: 130)
            Text("Add widgets to your desktop").font(.title2.weight(.bold)).foregroundStyle(theme.fg)
            VStack(alignment: .leading, spacing: 10) {
                step(1, "Right-click an empty spot on the desktop and choose Edit Widgets.")
                step(2, "Search for NexLauncher.")
                step(3, "Add Running Services to see live ports, or Quick Launch for your pinned projects (pin them in Settings → Projects).")
            }
            HStack {
                Button("Close") { dismiss() }
                Pill("I've added it") { model.confirmWidgetsAdded(); dismiss() }
            }
        }
        .padding(28).frame(width: 480).background(theme.canvas)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.caption.weight(.bold)).foregroundStyle(theme.onAccent)
                .frame(width: 20, height: 20).background(theme.accent, in: Circle())
            Text(text).foregroundStyle(theme.fg2).fixedSize(horizontal: false, vertical: true)
        }
    }
}
