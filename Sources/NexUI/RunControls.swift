import SwiftUI
import AppKit
import NexCore
import NexProcess

struct RunControls: View {
    @Bindable var model: AppModel
    let project: Project
    @State private var showDevices = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(model.availableActions(for: project), id: \.self) { action in
                Button(action.rawValue) { start(action) }
                    .buttonStyle(.glass)
                    .disabled(isActive(action))
                    .popover(isPresented: action == .flutter ? $showDevices : .constant(false)) {
                        FlutterDevicePicker(model: model, project: project, dismiss: { showDevices = false })
                    }
            }
            Spacer(minLength: 0)
            if model.isRunning(project) {
                Button(role: .destructive) { Task { await model.stop(project) } } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
            }
        }
        .controlSize(.regular)
    }

    private func isActive(_ action: RunAction) -> Bool {
        action.kinds.allSatisfy { kind in
            model.processes.states[ServiceID(projectID: project.id, kind: kind)]?.isActive == true
        }
    }

    private func start(_ action: RunAction) {
        if action == .flutter { showDevices = true; return }
        Task { await model.run(project, kinds: action.kinds) }
    }
}

struct ServiceStatusList: View {
    @Bindable var model: AppModel
    let project: Project

    private var rows: [(ServiceID, ServiceState)] {
        model.processes.states.filter { $0.key.projectID == project.id && $0.value != .stopped }
            .sorted { $0.key.kind.rawValue < $1.key.kind.rawValue }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows, id: \.0) { id, state in
                    HStack(spacing: 8) {
                        Circle().fill(color(state)).frame(width: 8, height: 8)
                        Text(id.kind.rawValue.capitalized).font(.callout.weight(.medium))
                        Text(label(state)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        if case .running(let port?) = state {
                            Button("Open") { NSWorkspace.shared.open(URL(string: "http://localhost:\(port)")!) }
                                .buttonStyle(.glass).controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private func color(_ s: ServiceState) -> Color {
        switch s {
        case .running: return .green
        case .starting: return .yellow
        case .failed: return .red
        case .stopped: return .gray
        }
    }

    private func label(_ s: ServiceState) -> String {
        switch s {
        case .starting: return "Starting…"
        case .running(let port): return port.map { "localhost:\($0)" } ?? "Running"
        case .failed(let message): return message
        case .stopped: return "Stopped"
        }
    }
}
