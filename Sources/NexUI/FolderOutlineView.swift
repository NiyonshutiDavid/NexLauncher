import SwiftUI
import NexCore

/// The Folders view: an expandable outline that mirrors the folders on disk. Folders load lazily as they open.
struct FolderOutlineView: View {
    @Bindable var model: AppModel
    let root: URL
    var openPage: (FolderEntry, Project?) -> AppPage = { entry, project in project.map { .project($0.id) } ?? .folder(entry.id) }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(FolderTree.entries(in: root)) { entry in
                OutlineRow(model: model, entry: entry, depth: 0, openPage: openPage)
            }
        }
    }
}

private struct OutlineRow: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    let entry: FolderEntry
    let depth: Int
    let openPage: (FolderEntry, Project?) -> AppPage
    @State private var expanded = false
    @State private var children: [FolderEntry] = []
    @State private var hovering = false

    private var project: Project? { model.projects.first { $0.root.path == entry.id } }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Button {
                    if !expanded && children.isEmpty { children = FolderTree.entries(in: entry.url) }
                    withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(theme.fg3)
                        .rotationEffect(.degrees(expanded ? 90 : 0)).frame(width: 18)
                        .opacity(entry.hasSubfolders ? 1 : 0)
                }
                .buttonStyle(.plain).disabled(!entry.hasSubfolders)

                Button { model.page = openPage(entry, project); model.detailTab = .overview } label: {
                    HStack(spacing: 10) {
                        if let project { IconTile(name: project.name, glyph: ProjectGlyph.symbol(for: project), size: 28) }
                        else { Image(systemName: entry.isApp ? "shippingbox" : "folder").foregroundStyle(theme.fg3).frame(width: 28) }
                        Text(entry.name).foregroundStyle(theme.fg).lineLimit(1)
                        if let project { Badge(text: ProjectSubtitle.text(for: project), tint: theme.fg2) }
                        if let g = model.gitBadges[entry.id], !g.isClean { Badge(text: "\(g.changes) changes", tint: theme.accent) }
                    }
                }
                .buttonStyle(.plain)

                Spacer()
                if let project { RunPill(model: model, project: project) }
                IconButton("terminal", help: "Open a terminal here") {
                    model.showTerminal(at: entry.url, page: openPage(entry, project))
                }
                .opacity(hovering || project != nil ? 1 : 0.0)
            }
            .padding(.leading, CGFloat(depth) * 22 + 6).padding(.trailing, 8).padding(.vertical, 5)
            .background(hovering ? theme.accentSoft.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onHover { hovering = $0 }

            if expanded {
                ForEach(children) { child in
                    OutlineRow(model: model, entry: child, depth: depth + 1, openPage: openPage)
                }
            }
        }
    }
}
