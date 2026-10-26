import SwiftUI
import AppKit
import NexCore
import NexProcess

/// The main App Store-style button on a card: Run (with a menu of choices) or Stop.
struct RunPill: View {
    @Bindable var model: AppModel
    let project: Project
    @State private var showDevices = false

    var body: some View {
        let actions = model.availableActions(for: project)
        if model.isRunning(project) {
            Pill("Stop", style: .destructive, systemImage: "stop.fill") { Task { await model.stop(project) } }
        } else if let primary = CardPrimaryAction.defaultAction(for: actions) {
            Menu {
                ForEach(actions, id: \.self) { action in
                    Button(action.rawValue) { start(action) }
                }
            } label: {
                PillLabel(CardPrimaryAction.title(running: false, actions: actions), systemImage: "play.fill")
            } primaryAction: {
                start(primary)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .popover(isPresented: $showDevices) {
                FlutterDevicePicker(model: model, project: project, dismiss: { showDevices = false })
            }
        }
    }

    private func start(_ action: RunAction) {
        if action == .flutter { showDevices = true; return }
        Task { await model.run(project, kinds: action.kinds) }
    }
}

struct ServiceStatusList: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    let project: Project

    private var rows: [(ServiceID, ServiceState)] {
        model.processes.states.filter { $0.key.projectID == project.id && $0.value != .stopped }
            .sorted { ($0.key.kind.rawValue, $0.key.directory) < ($1.key.kind.rawValue, $1.key.directory) }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows, id: \.0) { id, state in
                    HStack(spacing: 8) {
                        Circle().fill(color(state)).frame(width: 8, height: 8)
                        Text(title(for: id)).font(.callout.weight(.medium)).foregroundStyle(theme.fg)
                        Text(label(state)).font(.callout).foregroundStyle(theme.fg2).lineLimit(1)
                        Spacer()
                        if case .running(let port?) = state {
                            Button("Open") { NSWorkspace.shared.open(URL(string: "http://localhost:\(port)")!) }
                                .buttonStyle(.plain).font(.callout.weight(.semibold)).foregroundStyle(theme.accent)
                        }
                    }
                }
            }
        }
    }

    /// "Frontend", or "Frontend · admin" when the project has several services of that kind.
    private func title(for id: ServiceID) -> String {
        let same = model.processes.states.keys.filter { $0.projectID == project.id && $0.kind == id.kind }.count
        let name = id.kind.rawValue.capitalized
        return same > 1 ? "\(name) · \(URL(fileURLWithPath: id.directory).lastPathComponent)" : name
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
