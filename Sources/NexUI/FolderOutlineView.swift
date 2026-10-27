import SwiftUI
import NexCore
import NexApp

/// The Folders view: an expandable outline that mirrors the folders on disk. Folders load lazily as they open.
struct FolderOutlineView: View {
    @Bindable var model: AppModel
    let root: URL
    var openPage: (FolderEntry, Project?) -> AppPage = { entry, project in project.map { .project($0.id) } ?? .folder(entry.id) }
    @State private var entries: [FolderEntry] = []

    var body: some View {
        VStack(spacing: 2) {
            ForEach(entries) { entry in
                OutlineRow(model: model, entry: entry, depth: 0, openPage: openPage)
            }
        }
        // Listed once and again after each scan, never while rendering.
        .task(id: model.refreshToken) { entries = await Self.load(root) }
    }

    private static func load(_ root: URL) async -> [FolderEntry] {
        await Task.detached { FolderTree.entries(in: root) }.value
    }
}

/// The Folders view while a filter or search is active: only matching apps, as outline rows.
struct FilteredFolderRows: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 2) {
            ForEach(model.filteredProjects) { project in
                OutlineRow(model: model, entry: FolderEntry(id: project.root.path, name: project.name, url: project.root, isApp: true, hasSubfolders: false),
                           depth: 0, openPage: { _, p in p.map { .project($0.id) } ?? .folder(project.root.path) })
            }
        }
    }
}

struct OutlineRow: View {
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
                    if !expanded { children = FolderTree.entries(in: entry.url) }      // fresh on every open
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
                if let project {
                    RunPill(model: model, project: project)
                    IconButton(model.isPinned(project) ? "pin.fill" : "pin", help: model.isPinned(project) ? "Unpin" : "Pin") { model.togglePin(project) }
                }
                IconButton("terminal", help: "Open a terminal here") {
                    model.showTerminal(at: entry.url, page: openPage(entry, project))
                }
                .opacity(hovering || project != nil ? 1 : 0.0)
            }
            .padding(.leading, CGFloat(depth) * 22 + 6).padding(.trailing, 8).padding(.vertical, 5)
            .background(hovering ? theme.accentSoft.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onHover { hovering = $0 }
            .onChange(of: model.refreshToken) { _, _ in if expanded { children = FolderTree.entries(in: entry.url) } }

            if expanded {
                ForEach(children) { child in
                    OutlineRow(model: model, entry: child, depth: depth + 1, openPage: openPage)
                }
            }
        }
    }
}
