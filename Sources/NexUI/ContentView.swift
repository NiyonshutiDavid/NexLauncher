import SwiftUI
import NexCore

public struct ContentView: View {
    @Bindable var model: AppModel
    @State private var path: [Project] = []

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        NavigationSplitView {
            List(ProjectFilter.allCases, selection: $model.filter) { filter in
                Label(filter.rawValue, systemImage: filter.symbol).tag(filter)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 200)
        } detail: {
            NavigationStack(path: $path) {
                ProjectGridView(model: model)
                    .navigationDestination(for: Project.self) { ProjectDetailView(model: model, project: $0) }
            }
        }
        .confirmationDialog(
            "Install dependencies first?",
            isPresented: Binding(get: { model.pendingInstall != nil }, set: { if !$0 { model.cancelInstall() } }),
            presenting: model.pendingInstall
        ) { pending in
            Button("Run npm install, then start") { Task { await model.confirmInstall() } }
            Button("Cancel", role: .cancel) { model.cancelInstall() }
        } message: { pending in
            Text("\(pending.project.name) has no node_modules folder yet.")
        }
    }
}
