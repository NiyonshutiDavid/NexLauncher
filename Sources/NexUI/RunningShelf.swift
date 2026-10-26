import SwiftUI
import AppKit
import NexCore
import NexProcess

struct RunningShelf: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    private var running: [Project] { model.projects.filter { model.isRunning($0) } }

    var body: some View {
        if !running.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Running now")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(running) { project in
                            CardSurface {
                                HStack(spacing: 12) {
                                    IconTile(name: project.name, glyph: ProjectGlyph.symbol(for: project), size: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(project.name).font(.callout.weight(.semibold)).foregroundStyle(theme.fg).lineLimit(1)
                                        Text(portsText(project)).font(.caption).foregroundStyle(theme.fg2)
                                    }
                                    Spacer(minLength: 10)
                                    if let port = firstPort(project) {
                                        Button("Open") { NSWorkspace.shared.open(URL(string: "http://localhost:\(port)")!) }
                                            .buttonStyle(.plain).font(.callout.weight(.semibold)).foregroundStyle(theme.accent)
                                    }
                                    Pill("Stop", style: .destructive) { Task { await model.stop(project) } }
                                }
                                .padding(14)
                            }
                            .frame(width: 340)
                            .hoverLift()
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                            .onTapGesture { model.page = .project(project.id); model.detailTab = .logs }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollClipDisabled()
            }
        }
    }

    private func ports(_ p: Project) -> [Int] {
        model.processes.states.compactMap { id, state in
            guard id.projectID == p.id, case .running(let port?) = state else { return nil }
            return port
        }.sorted()
    }
    private func firstPort(_ p: Project) -> Int? { ports(p).first }
    private func portsText(_ p: Project) -> String {
        let list = ports(p)
        return list.isEmpty ? "Starting…" : list.map { "localhost:\($0)" }.joined(separator: " · ")
    }
}
