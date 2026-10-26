import SwiftUI
import NexCore

struct ProjectGridView: View {
    @Bindable var model: AppModel

    private var subtitle: String {
        let total = model.projects.count
        let running = model.processes.runningCount
        if model.isScanning && total == 0 { return "Looking for projects…" }
        return "\(total) projects found" + (running > 0 ? " · \(running) running" : "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GreetingHeader(greeting: model.greeting, subtitle: subtitle)
                if model.filteredProjects.isEmpty && !model.isScanning {
                    ContentUnavailableView(
                        model.projects.isEmpty ? "No projects found" : "Nothing matches",
                        systemImage: "folder.badge.questionmark",
                        description: Text(model.projects.isEmpty
                            ? "Looked in \(model.settings.settings.scanRoot.path)"
                            : "Try a different search or filter."))
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    GlassEffectContainer(spacing: 20) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 480), spacing: 20)], spacing: 20) {
                            ForEach(model.filteredProjects) { ProjectCard(model: model, project: $0) }
                        }
                    }
                }
            }
            .padding(28)
        }
        .searchable(text: $model.searchText, prompt: "Search projects")
        .toolbar {
            ToolbarItem {
                Button { Task { await model.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .help("Scan for projects again")
            }
        }
        .navigationTitle("")
    }
}
