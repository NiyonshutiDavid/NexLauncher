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
    @State private var isFullScreen = false

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            page
                .safeAreaPadding(.top, isFullScreen ? HeaderMetrics.windowToolbarBand : 0)
                .id(pageKey)
                .transition(.opacity.combined(with: .offset(x: 18)))
                .background(theme.canvas)
                .animation(.smooth(duration: 0.3), value: pageKey)
                // An invisible item: with an empty toolbar macOS drops the sidebar panel below the window controls.
                .toolbar { ToolbarSpacer(.flexible) }
        }
        // The header is drawn by each page (FadingHeader), WhatsApp-style: in a window its controls go in the
        // transparent system toolbar (which also keeps the window controls inside the sidebar); in full screen
        // the toolbar is hidden and the page draws them.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .environment(\.windowIsFullScreen, isFullScreen)
        .environment(\.modalIsOpen, modalKey != nil)
        .background(WindowStyler(isFullScreen: $isFullScreen))
        .overlay {
            if model.showOnboarding { OnboardingView(model: model).transition(.opacity) }
        }
        .animation(.easeInOut(duration: 0.3), value: model.showOnboarding)
        .overlay {
            ZStack {
                if let session = model.setup {
                    ModalLayer(onClose: {}) { SetupSheet(model: model, session: session) }   // closes through its own buttons
                } else if let sheet = model.sheet {
                    ModalLayer(onClose: { model.sheet = nil }) {
                        switch sheet {
                        case .addProject(let mode): AddProjectSheet(model: model, initialMode: mode)
                        case .widgetsHowTo: WidgetsHowToSheet(model: model)
                        }
                    }
                } else if let modal = model.modal {
                    ModalLayer(onClose: { model.modal = nil }) { modal.view }
                }
            }
            .animation(.spring(duration: 0.35), value: modalKey)
        }
    }

    /// Which pop-up is showing, if any.
    private var modalKey: String? {
        if let setup = model.setup { return "setup-\(setup.id)" }
        if let sheet = model.sheet { return sheet.id }
        return model.modal.map { "modal-\($0.id)" }
    }

    /// Changes when the page (or the sidebar section) changes, so the detail fades and slides in.
    private var pageKey: String { "\(model.page)|\(model.filter.rawValue)|\(model.showOnlyUncommitted)" }

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
