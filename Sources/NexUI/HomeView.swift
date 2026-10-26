import SwiftUI
import NexCore

struct HomeView: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    private var subtitle: String {
        let total = model.projects.count
        let running = model.processes.runningCount
        if model.isScanning && total == 0 { return "Looking for projects…" }
        return "\(total) project\(total == 1 ? "" : "s")" + (running > 0 ? " · \(running) running" : "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                GreetingHeader(greeting: model.greeting, subtitle: subtitle)
                CTAShelf(model: model)
                PinnedShelf(model: model)
                RunningShelf(model: model)

                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(model.showOnlyUncommitted ? "Unsaved changes" : model.filter.rawValue,
                                  actionTitle: model.showOnlyUncommitted ? "Show all" : nil,
                                  action: model.showOnlyUncommitted ? { model.showOnlyUncommitted = false } : nil)
                    if let empty = model.emptyState {
                        EmptyStateView(model: model, kind: empty)
                    } else if model.viewMode == .folders {
                        if model.isFiltering { FilteredFolderRows(model: model) }
                        else { FolderOutlineView(model: model, root: model.settings.settings.scanRoot) }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: 520), spacing: 20)], spacing: 20) {
                            ForEach(model.homeItems) { item in
                                switch item {
                                case .project(let project): ProjectCard(model: model, project: project)
                                case .collection(let node): CollectionCard(model: model, node: node)
                                }
                            }
                        }
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentMargins(.top, GlassHeaderMetrics.inset, for: .scrollContent)
        .glassHeader(title: headerTitle) {
            EmptyView()
        } trailing: {
            GlassSearchField(text: $model.searchText)
            Picker("View", selection: $model.viewMode) {
                Label("Cards", systemImage: "square.grid.2x2").tag(ViewMode.cards)
                Label("Folders", systemImage: "list.bullet.indent").tag(ViewMode.folders)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 116)
            .help("Switch between cards and the folder structure")
            Menu {
                Button("New folder…", systemImage: "folder.badge.plus") { model.sheet = .addProject(.newFolder) }
                Button("Clone repository…", systemImage: "arrow.down.circle") { model.sheet = .addProject(.clone) }
            } label: {
                Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(theme.onAccent)
                    .frame(width: 32, height: 32)
                    .background(theme.accent, in: Circle())                       // filled, so it reads as the primary action
                    .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
                    .shadow(color: theme.accent.opacity(0.4), radius: 6, y: 2)
                    .contentShape(Circle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help("Add a project")
            IconButton("arrow.clockwise", help: "Scan for projects again") { Task { await model.refresh() } }
        }
    }

    private var headerTitle: String { model.showOnlyUncommitted ? "Unsaved changes" : "Projects" }
}
