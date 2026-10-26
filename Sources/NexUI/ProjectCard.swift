import SwiftUI
import NexCore
import NexProcess

struct Badge: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }
}

struct ProjectCard: View {
    @Bindable var model: AppModel
    let project: Project

    private var badges: [(String, Color)] {
        var out: [(String, Color)] = []
        if project.isFullStack { out.append(("Full-stack", .green)) }
        else if project.targets.contains(where: { $0.kind == .frontend }) { out.append(("Frontend", .blue)) }
        else if project.targets.contains(where: { $0.kind == .backend }) { out.append(("Backend", .orange)) }
        if project.targets.contains(where: { $0.kind == .flutter }) { out.append(("Flutter", .cyan)) }
        if project.targets.contains(where: { $0.kind == .docker }) { out.append(("Docker", .indigo)) }
        return out
    }

    private func gitText(_ g: GitBadge) -> String {
        var parts: [String] = []
        if g.changes > 0 { parts.append("\(g.changes) change\(g.changes == 1 ? "" : "s")") }
        if g.ahead > 0 { parts.append("↑\(g.ahead)") }
        if g.behind > 0 { parts.append("↓\(g.behind)") }
        return "git · " + (parts.isEmpty ? "clean" : parts.joined(separator: " "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(value: project) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(project.name).font(.title3.weight(.semibold)).lineLimit(1)
                        HStack(spacing: 6) {
                            ForEach(badges, id: \.0) { Badge(text: $0.0, tint: $0.1) }
                            if let g = model.gitBadges[project.id] {
                                Badge(text: gitText(g), tint: g.isClean ? .secondary : .yellow)
                            }
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            RunControls(model: model, project: project)
            ServiceStatusList(model: model, project: project)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}
