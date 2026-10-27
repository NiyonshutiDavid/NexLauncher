import Foundation
import Adwaita
import NexApp
import NexCore

struct HomePage: View {
    let model: AppModel
    @State private var filtersOpen = false

    private var title: String {
        model.showOnlyUncommitted ? "Unsaved changes" : (model.filter == .all ? "Projects" : model.filter.rawValue)
    }

    var view: Body {
        ScrollView {
            VStack(spacing: 18) {
                if model.filter == .all && !model.showOnlyUncommitted {
                    Text(model.greeting).style("title-1").halign(.start)
                    Text(HomeText.projectsIn(model.projects.count)).style("dim-label").halign(.start)
                }
                Form {
                    EntryRow("Search projects", text: Binding(get: { model.searchText }, set: { model.searchText = $0 }))
                }
                if model.filters.isActive {
                    FilterChips(model: model)
                }
                if model.isScanning && model.projects.isEmpty {
                    Spinner().halign(.center).padding(40)
                } else if let empty = model.emptyState {
                    EmptyStateView(model: model, kind: empty)
                } else {
                    FlowBox(model.homeItems) { item in
                        HomeItemCard(model: model, item: item)
                    }
                    .valign(.start)
                }
            }
            .padding(24)
            .frame(maxWidth: 1100)
        }
        .topToolbar {
            HeaderBar {
                Button(icon: .default(icon: .viewRefresh)) { Task { await model.refresh() } }
                    .tooltip("Scan for projects again")
                Button(icon: .custom(name: "view-more-horizontal-symbolic")) { filtersOpen = true }
                    .tooltip("Filter projects")
                    .popover(visible: $filtersOpen) { FilterPanel(model: model) }
            } end: {
                Button(icon: .default(icon: .listAdd)) { model.sheet = .addProject(.newFolder) }
                    .suggested()
                    .tooltip("Add a project")
            }
            .headerBarTitle { WindowTitle(subtitle: "", title: title) }
        }
    }
}

struct HomeItemCard: View {
    let model: AppModel
    let item: HomeItem

    var view: Body {
        switch item {
        case .project(let project): ProjectCard(model: model, project: project)
        case .collection(let node): CollectionCard(model: model, node: node)
        }
    }
}

struct ProjectCard: View {
    let model: AppModel
    let project: Project

    private var actions: [RunAction] { model.availableActions(for: project) }
    private var running: Bool { model.isRunning(project) }

    var view: Body {
        VStack(spacing: 6) {
            Text(project.name).style("heading").halign(.start).ellipsize()
            Text(ProjectSubtitle.text(for: project)).style("dim-label").halign(.start).ellipsize()
            HStack(spacing: 6) {
                if running {
                    Button("Stop") { Task { await model.stop(project) } }.destructive().pill()
                } else if let action = CardPrimaryAction.defaultAction(for: actions) {
                    Button(CardPrimaryAction.title(running: false, actions: actions)) {
                        Task { await model.run(project, kinds: action.kinds) }
                    }
                    .suggested().pill()
                }
                Button(icon: .custom(name: model.isPinned(project) ? "starred-symbolic" : "non-starred-symbolic")) {
                    model.togglePin(project)
                }
                .flat()
                .tooltip(model.isPinned(project) ? "Unpin" : "Pin")
                if let badge = model.gitBadges[project.id], badge.repoCount > 0 {
                    Text(badge.isClean ? "git · clean" : "git · \(badge.changes) changes").style("caption").style("dim-label")
                }
            }
        }
        .padding(16)
        .frame(minWidth: 300)
        .style("card")
        .onClick { model.page = .project(project.id) }
    }
}

struct CollectionCard: View {
    let model: AppModel
    let node: ProjectNode

    var view: Body {
        VStack(spacing: 6) {
            Text(node.name).style("heading").halign(.start)
            Text("Collection · \(HomeText.projectsIn(node.apps.count))").style("dim-label").halign(.start)
        }
        .padding(16)
        .frame(minWidth: 300)
        .style("card")
        .onClick { model.page = .collection(node.id) }
    }
}

struct CollectionPage: View {
    let model: AppModel
    let node: ProjectNode

    var view: Body {
        ScrollView {
            VStack(spacing: 18) {
                Text(node.name).style("title-1").halign(.start)
                Text(HomeText.projectsIn(node.apps.count)).style("dim-label").halign(.start)
                FlowBox(node.children.map { child in
                    child.kind == .collection ? HomeItem.collection(child) : HomeItem.project(child.project!)
                }) { item in
                    HomeItemCard(model: model, item: item)
                }
            }
            .padding(24)
            .frame(maxWidth: 1100)
        }
        .topToolbar { BreadcrumbHeader(model: model) }
    }
}

struct EmptyStateView: View {
    let model: AppModel
    let kind: EmptyStateKind

    var view: Body {
        if kind == .noProjects {
            StatusPage("Nothing here yet", icon: .default(icon: .folder),
                       description: "No projects found in \(model.settings.settings.scanRoot.path).") {
                Button("Add project") { model.sheet = .addProject(.newFolder) }.suggested().pill().halign(.center)
            }
        } else {
            StatusPage("No matches", icon: .default(icon: .systemSearch), description: "Try another search or clear the filters.") {
                Button("Clear filters") { model.searchText = ""; model.clearFilters(); model.select(filter: .all) }.pill().halign(.center)
            }
        }
    }
}
