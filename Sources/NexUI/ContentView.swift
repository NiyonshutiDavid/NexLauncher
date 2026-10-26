import SwiftUI
import NexCore

public struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        RootContent(model: model)
            .nexTheme(model.settings.settings.theme, appearance: model.settings.settings.appearance)
    }
}

private struct RootContent: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240)
                .toolbar(removing: .sidebarToggle)            // WhatsApp-style: only the window controls up there
        } detail: {
            page
                .background(theme.canvas)
        }
        .overlay {
            if model.showOnboarding { OnboardingView(model: model).transition(.opacity) }
        }
        .animation(.easeInOut(duration: 0.3), value: model.showOnboarding)
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .addProject(let mode): AddProjectSheet(model: model, initialMode: mode)
            case .widgetsHowTo: WidgetsHowToSheet(model: model)
            }
        }
        .sheet(item: $model.setup) { session in SetupSheet(model: model, session: session) }
    }

    @ViewBuilder private var page: some View {
        switch model.page {
        case .home: HomeView(model: model)
        case .settings(let section): SettingsPage(model: model, section: section)
        case .collection(let id):
            if let node = model.node(id: id) { CollectionView(model: model, node: node) } else { HomeView(model: model) }
        case .project(let id):
            if let project = model.project(id: id) { ProjectDetailView(model: model, project: project, folder: project.root) }
            else { HomeView(model: model) }
        case .folder(let path): ProjectDetailView(model: model, project: nil, folder: URL(fileURLWithPath: path))
        case .tasks: TasksPage(model: model)
        case .ai: AIPage(model: model)
        }
    }
}
