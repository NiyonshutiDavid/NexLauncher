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

    /// Each sidebar section gets its own banner, illustration and next step.
    @ViewBuilder private var pageHero: some View {
        if model.showOnlyUncommitted {
            HeroBanner(eyebrow: "Git", title: "Unsaved changes", subtitle: "These projects have changes that aren't committed yet. Open one and use the Git tab to commit.",
                       illustration: .branchGraph, actions: [HeroAction(title: "Show all projects", style: .quiet) { model.showOnlyUncommitted = false }])
        } else {
            switch model.filter {
            case .all:
                EmptyView()
            case .pinned:
                let n = model.pinnedProjects.count
                HeroBanner(eyebrow: "Pinned", title: n == 0 ? "Keep favourites close" : "\(n) pinned project\(n == 1 ? "" : "s")",
                           subtitle: "Pinned projects appear in the menu bar panel (⌥⌘L), the Dock menu and the Quick Launch widget.",
                           illustration: .pin,
                           actions: n == 0 ? [HeroAction(title: "Browse projects", systemImage: "square.grid.2x2") { model.select(filter: .all) }]
                                           : [HeroAction(title: "Add the widget", systemImage: "rectangle.3.group", style: .quiet) { model.sheet = .widgetsHowTo }])
            case .running:
                let running = model.runningProjects
                let last = model.settings.settings.lastRun.flatMap { r in model.project(id: r.projectID) }
                HeroBanner(eyebrow: "Running", title: running.isEmpty ? "Nothing is running" : "\(model.processes.runningCount) service\(model.processes.runningCount == 1 ? "" : "s") running",
                           subtitle: running.isEmpty ? "Start a project and it shows up here with its ports and logs." : "Open them in your browser, read their logs, or stop everything at once.",
                           illustration: .play,
                           actions: running.isEmpty
                               ? (last.map { p in [HeroAction(title: "Run \(p.name)", systemImage: "play.fill") { Task { await model.toggleRun(p) } }] } ?? [])
                               : [HeroAction(title: "Stop all", systemImage: "stop.fill", style: .destructive) { Task { await model.stopAllServices() } }])
            case .fullStack:
                HeroBanner(eyebrow: "Full-stack", title: "Both ends, one click",
                           subtitle: "These projects have a frontend and a backend. Run Both starts them together.",
                           illustration: .layers,
                           actions: [HeroAction(title: "Add project", systemImage: "plus") { model.sheet = .addProject(.newFolder) }])
            case .flutter:
                HeroBanner(eyebrow: "Flutter", title: "Simulators & emulators",
                           subtitle: "Launch an iOS simulator or an Android emulator from Android Studio, then run your app on it.",
                           illustration: .phone)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if model.filter == .all && !model.showOnlyUncommitted {
                    GreetingHeader(greeting: model.greeting, subtitle: subtitle)
                    CTAShelf(model: model)
                    PinnedShelf(model: model)
                    RunningShelf(model: model)
                } else {
                    pageHero
                }
                if model.isScanning { ScanningBanner().transition(.opacity) }

                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(model.showOnlyUncommitted ? "Unsaved changes" : model.filter.rawValue,
                                  actionTitle: model.showOnlyUncommitted ? "Show all" : nil,
                                  action: model.showOnlyUncommitted ? { model.showOnlyUncommitted = false } : nil)
                    if model.isScanning && model.projects.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: 520), spacing: 20)], spacing: 20) {
                            ForEach(0..<6, id: \.self) { _ in SkeletonCard() }
                        }
                    } else if let empty = model.emptyState {
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
            .animation(.easeInOut(duration: 0.25), value: model.isScanning)
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search projects")
        .navigationTitle("")
        .toolbar {
            ToolbarItem {
                Picker("View", selection: $model.viewMode) {
                    Label("Cards", systemImage: "square.grid.2x2").tag(ViewMode.cards)
                    Label("Folders", systemImage: "list.bullet.indent").tag(ViewMode.folders)
                }
                .pickerStyle(.segmented)
                .help("Switch between cards and the folder structure")
            }
            ToolbarItem { AddProjectToolbarButton(model: model) }
            ToolbarItem {
                Button { Task { await model.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .help("Scan for projects again")
            }
        }
    }

}

/// The primary "add" action: a filled accent circle so it stands out from the other toolbar buttons.
struct AddProjectToolbarButton: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        Menu {
            Button("New folder…", systemImage: "folder.badge.plus") { model.sheet = .addProject(.newFolder) }
            Button("Clone repository…", systemImage: "arrow.down.circle") { model.sheet = .addProject(.clone) }
        } label: {
            Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundStyle(theme.onAccent)
                .frame(width: 28, height: 28)
                .background(theme.accent, in: Circle())
                .contentShape(Circle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("Add a project")
    }
}
