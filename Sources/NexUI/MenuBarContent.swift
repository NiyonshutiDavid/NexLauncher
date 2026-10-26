import SwiftUI
import AppKit
import NexCore

public struct MenuBarContent: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.greeting).font(.headline)
                Spacer()
                Text(model.processes.runningCount > 0 ? "\(model.processes.runningCount) running" : "Nothing running")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.projects.sorted { model.isRunning($0) && !model.isRunning($1) }) { project in
                        MenuBarRow(model: model, project: project)
                    }
                    if model.projects.isEmpty {
                        Text("No projects found").foregroundStyle(.secondary).padding(.vertical, 20)
                    }
                }
            }
            .frame(maxHeight: 360)
            Divider()
            HStack {
                Button("Open NexLauncher") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.glass)
        }
        .padding(14)
        .frame(width: 340)
        .task { if model.projects.isEmpty { await model.refresh() } }
    }
}

private struct MenuBarRow: View {
    let model: AppModel
    let project: Project

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(model.isRunning(project) ? Color.green : Color.gray.opacity(0.4)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name).lineLimit(1)
                if let g = model.gitBadges[project.id], !g.isClean {
                    Text("\(g.changes) uncommitted").font(.caption2).foregroundStyle(.yellow)
                }
            }
            Spacer()
            if model.isRunning(project) {
                Button { Task { await model.stop(project) } } label: { Image(systemName: "stop.fill") }
                    .buttonStyle(.glass).tint(.red).help("Stop")
            } else {
                Menu {
                    ForEach(model.availableActions(for: project), id: \.self) { action in
                        Button(action.rawValue) { Task { await model.run(project, kinds: action.kinds) } }
                            .disabled(action == .flutter)   // device choice lives in the main window
                    }
                } label: { Image(systemName: "play.fill") }
                .menuStyle(.borderlessButton).fixedSize()
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}
