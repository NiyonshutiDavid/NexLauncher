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
                header

                Picker("", selection: $model.detailTab) {
                    ForEach(tabs) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(minWidth: 0, maxWidth: 460)

                content
            }
            .padding(aiPanelOpen ? 24 : 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 0)
        .fadingHeader(crumbs: crumbs, onSelect: { model.page = $0 }) {
            HeaderBackButton { model.goBack() }
        } trailing: {
            if let project {
                HeaderCircleButton(symbol: "sparkles", help: aiPanelOpen ? "Hide the AI assistant" : "Ask AI about this project") {
                    withAnimation(.spring(duration: 0.35)) { model.toggleAIPanel(for: project) }
                }
                RunPill(model: model, project: project)
            }
        }
        .inspector(isPresented: aiPanelBinding) {
            if let project {
                ProjectAIPanel(model: model, project: project)
                    .inspectorColumnWidth(min: 320, ideal: 380, max: 520)
            }
        }
    }

    private var crumbs: [Crumb] {
        let trail = model.breadcrumbs(for: model.page)
        return trail.isEmpty ? [Crumb(title: "Projects", page: .home), Crumb(title: project?.name ?? folder.lastPathComponent, page: nil)] : trail
    }

    private var aiPanelOpen: Bool { project != nil && model.aiPanelProjectID == project?.id }

    private var aiPanelBinding: Binding<Bool> {
        Binding(get: { aiPanelOpen }, set: { if !$0 { model.aiPanelProjectID = nil } })
    }

    private var header: some View {
        HStack(spacing: 18) {
            // Smaller tile while the AI panel shares the window, so the page still fits beside it.
            if let project { IconTile(name: project.name, glyph: ProjectGlyph.symbol(for: project), size: aiPanelOpen ? 64 : 88) }
            else { IconTile(name: folder.lastPathComponent, glyph: "folder.fill", size: 88) }
            VStack(alignment: .leading, spacing: 6) {
                Text(project?.name ?? folder.lastPathComponent).font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(theme.fg)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(project.map(ProjectSubtitle.text(for:)) ?? "Folder").font(.title3).foregroundStyle(theme.fg2)
                FlowLayout(spacing: 10) {
                    if let project {
                        RunPill(model: model, project: project)
                        IconButton(model.isPinned(project) ? "pin.fill" : "pin", help: model.isPinned(project) ? "Unpin" : "Pin to menu bar, Dock and widget") { model.togglePin(project) }
                    }
                    IconButton("terminal", help: "Open a terminal here") { model.showTerminal(at: folder, page: model.page) }
                    IconButton("folder", help: "Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                    if let project {
                        Pill(aiPanelOpen ? "Hide AI" : "Ask AI", style: .quiet, systemImage: "sparkles") {
                            withAnimation(.spring(duration: 0.35)) { model.toggleAIPanel(for: project) }
                        }
                    }
                }
                .padding(.top, 4)
            }
            Spacer()
        }
    }

    @ViewBuilder private var content: some View {
        switch model.detailTab {
        case .overview: overview
        case .tasks: if let project { ProjectTasksTab(model: model, project: project) }
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
