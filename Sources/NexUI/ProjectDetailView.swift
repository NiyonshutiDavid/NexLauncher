import SwiftUI
import NexCore

struct ProjectDetailView: View {
    @Bindable var model: AppModel
    let project: Project
    @State private var tab: Tab = .logs

    enum Tab: String, CaseIterable { case logs = "Services", git = "Git" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(project.name).font(.system(size: 30, weight: .bold, design: .rounded))
            RunControls(model: model, project: project)
            ServiceStatusList(model: model, project: project)
            Picker("", selection: $tab) { ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).frame(maxWidth: 240).labelsHidden()
            switch tab {
            case .logs: LogPanel(model: model, project: project)
            case .git: GitPanelView(model: model, project: project)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(project.name)
    }
}
