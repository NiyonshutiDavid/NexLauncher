import SwiftUI
import AppKit
import NexCore

public struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var login = LaunchAtLogin()

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        Form {
            Section("General") {
                Toggle("Launch NexLauncher when I log in", isOn: Binding(get: { login.isEnabled }, set: { login.set($0) }))
                if let error = login.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
                Toggle("Show icon in the Dock", isOn: Binding(
                    get: { model.settings.settings.showDockIcon },
                    set: { model.settings.settings.showDockIcon = $0; model.settings.save(); model.applyDockIconPolicy() }))
                TextField("Name in greeting", text: Binding(
                    get: { model.settings.settings.displayName },
                    set: { model.settings.settings.displayName = $0; model.settings.save() }))
            }
            Section("Projects folder") {
                HStack {
                    Text(model.settings.settings.scanRoot.path).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { chooseFolder() }
                }
            }
            Section("Pinned for widgets") {
                if model.projects.isEmpty { Text("No projects yet").foregroundStyle(.secondary) }
                ForEach(model.projects) { project in
                    Toggle(project.name, isOn: Binding(
                        get: { model.settings.settings.pinnedProjectIDs.contains(project.id) },
                        set: { on in
                            var ids = model.settings.settings.pinnedProjectIDs.filter { $0 != project.id }
                            if on { ids.append(project.id) }
                            model.settings.settings.pinnedProjectIDs = ids
                            model.settings.save()
                            model.publishSnapshot()
                        }))
                }
            }
            Section("Commands") {
                Text("Detected commands can be overridden per project (command and port).")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.projects) { project in
                    ForEach(project.targets, id: \.directory) { target in
                        OverrideRow(model: model, target: target, projectName: project.name)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 560)
        .onAppear { login.refresh() }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = model.settings.settings.scanRoot
        if panel.runModal() == .OK, let url = panel.url {
            model.settings.settings.scanRoot = url
            model.settings.save()
            Task { await model.refresh() }
        }
    }
}

private struct OverrideRow: View {
    let model: AppModel
    let target: ServiceTarget
    let projectName: String
    @State private var command = ""
    @State private var port = ""

    private var key: String { OverrideStore.key(directory: target.directory, kind: target.kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(projectName) · \(target.kind.rawValue)").font(.callout.weight(.medium))
            TextField("Command", text: $command, onCommit: save).font(.system(.caption, design: .monospaced))
            TextField("Port (optional)", text: $port, onCommit: save).frame(width: 140)
        }
        .onAppear {
            let o = model.overrides.override(forPath: key)
            command = o?.command ?? target.command
            port = o?.port.map(String.init) ?? ""
        }
    }

    private func save() {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        let custom = trimmed.isEmpty || trimmed == target.command ? nil : trimmed
        let p = Int(port)
        model.overrides.set(custom == nil && p == nil ? nil : Override(command: custom, port: p), forPath: key)
        Task { await model.refresh() }
    }
}
