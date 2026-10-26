import SwiftUI
import NexCore

struct ProjectCard: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    let project: Project

    private var nestedCount: Int { model.node(id: project.id)?.children.count ?? 0 }

    var body: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    IconTile(name: project.name, glyph: ProjectGlyph.symbol(for: project), size: 60)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.name).font(.headline.weight(.semibold)).foregroundStyle(theme.fg).lineLimit(1)
                        Text(ProjectSubtitle.text(for: project)).font(.subheadline).foregroundStyle(theme.fg2).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    RunPill(model: model, project: project)
                }
                HStack(spacing: 8) {
                    if let g = model.gitBadges[project.id] { Badge(text: gitText(g), tint: g.isClean ? theme.fg3 : theme.accent) }
                    if nestedCount > 0 { Badge(text: HomeText.appsInside(nestedCount), tint: theme.fg2) }
                    Spacer()
                    IconButton("terminal", help: "Open a terminal here") {
                        model.showTerminal(at: project.root, page: .project(project.id))
                    }
                }
                ServiceStatusList(model: model, project: project)
            }
            .padding(18)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .onTapGesture { model.page = .project(project.id); model.detailTab = .overview }
    }

    private func gitText(_ g: GitBadge) -> String {
        var parts: [String] = []
        if g.changes > 0 { parts.append("\(g.changes) change\(g.changes == 1 ? "" : "s")") }
        if g.ahead > 0 { parts.append("↑\(g.ahead)") }
        if g.behind > 0 { parts.append("↓\(g.behind)") }
        return "git · " + (parts.isEmpty ? "clean" : parts.joined(separator: " "))
    }
}

struct CollectionCard: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    let node: ProjectNode

    var body: some View {
        CardSurface {
            HStack(spacing: 14) {
                IconTile(name: node.name, glyph: "folder.fill", size: 60)
                VStack(alignment: .leading, spacing: 6) {
                    Text(node.name).font(.headline.weight(.semibold)).foregroundStyle(theme.fg).lineLimit(1)
                    Text("Collection · \(HomeText.projectsIn(node.apps.count))").font(.subheadline).foregroundStyle(theme.fg2)
                    HStack(spacing: -10) {
                        ForEach(Array(node.apps.prefix(5)), id: \.id) { app in
                            IconTile(name: app.name, glyph: ProjectGlyph.symbol(for: app), size: 24)
                                .overlay(Circle().strokeBorder(theme.surface, lineWidth: 0))
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(theme.fg3)
            }
            .padding(18)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .onTapGesture { model.page = .collection(node.id) }
    }
}

/// Renders one `ProjectNode` as the right kind of card.
struct NodeCard: View {
    let model: AppModel
    let node: ProjectNode

    var body: some View {
        if node.kind == .collection { CollectionCard(model: model, node: node) }
        else if let project = node.project { ProjectCard(model: model, project: project) }
    }
}
