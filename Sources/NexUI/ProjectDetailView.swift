import SwiftUI
import AppKit
import NexCore

/// Product-page style detail for a project or any folder: header, then Overview · Terminal · Logs · Git · Files.
struct ProjectDetailView: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    let project: Project?
    let folder: URL

    private var tabs: [DetailTab] { project == nil ? [.overview, .terminal, .git, .files] : DetailTab.allCases }
    private var nested: [ProjectNode] { project.flatMap { model.node(id: $0.id)?.children } ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Button { model.page = .home } label: {
                    Label("Projects", systemImage: "chevron.left").font(.callout.weight(.medium)).foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)

                header

                Picker("", selection: $model.detailTab) {
                    ForEach(tabs) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 460)

                content
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(spacing: 18) {
            if let project { IconTile(name: project.name, glyph: ProjectGlyph.symbol(for: project), size: 88) }
            else { IconTile(name: folder.lastPathComponent, glyph: "folder.fill", size: 88) }
            VStack(alignment: .leading, spacing: 6) {
                Text(project?.name ?? folder.lastPathComponent).font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(theme.fg)
                Text(project.map(ProjectSubtitle.text(for:)) ?? "Folder").font(.title3).foregroundStyle(theme.fg2)
                HStack(spacing: 10) {
                    if let project {
                        RunPill(model: model, project: project)
                        IconButton(model.isPinned(project) ? "pin.fill" : "pin", help: model.isPinned(project) ? "Unpin" : "Pin to menu bar, Dock and widget") { model.togglePin(project) }
                    }
                    IconButton("terminal", help: "Open a terminal here") { model.showTerminal(at: folder, page: model.page) }
                    IconButton("folder", help: "Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                }
                .padding(.top, 4)
            }
            Spacer()
        }
    }

    @ViewBuilder private var content: some View {
        switch model.detailTab {
        case .overview: overview
        case .terminal: TerminalPanel(model: model, directory: folder)
        case .logs: if let project { LogPanel(model: model, project: project) }
        case .git: GitPanelView(model: model, root: folder, title: project?.name ?? folder.lastPathComponent)
        case .files: FolderOutlineView(model: model, root: folder)
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let project {
                ServiceStatusList(model: model, project: project)
                SectionHeader("What's inside")
                VStack(spacing: 10) {
                    ForEach(project.targets, id: \.self) { target in
                        CardSurface {
                            HStack(spacing: 12) {
                                Badge(text: target.kind.rawValue.capitalized, tint: theme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(target.framework ?? target.kind.rawValue.capitalized).font(.callout.weight(.semibold)).foregroundStyle(theme.fg)
                                    Text(relativePath(target.directory)).font(.caption).foregroundStyle(theme.fg2)
                                }
                                Spacer()
                                IconButton("terminal", help: "Open a terminal in this folder") { model.showTerminal(at: target.directory, page: model.page) }
                            }
                            .padding(14)
                        }
                    }
                }
            }
            if !nested.isEmpty {
                SectionHeader("Apps inside")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: 520), spacing: 20)], spacing: 20) {
                    ForEach(nested) { NodeCard(model: model, node: $0) }
                }
            }
            if project == nil {
                CardSurface {
                    VStack(spacing: 8) {
                        IllustrationView(.folders).frame(width: 120, height: 120)
                        Text("No runnable app detected here yet").font(.headline).foregroundStyle(theme.fg)
                        Text("Add a package.json, pubspec.yaml, manage.py or docker-compose.yml and it will appear as a project. Meanwhile you can use the terminal and git.")
                            .multilineTextAlignment(.center).foregroundStyle(theme.fg2).frame(maxWidth: 440)
                    }
                    .padding(20).frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func relativePath(_ url: URL) -> String {
        let base = (project?.root ?? folder).path
        let rel = url.path.replacingOccurrences(of: base, with: "")
        return rel.isEmpty ? "/" : rel
    }
}
