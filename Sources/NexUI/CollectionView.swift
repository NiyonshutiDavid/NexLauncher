import SwiftUI
import NexCore

struct CollectionView: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    let node: ProjectNode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HeroBanner(eyebrow: "Collection", title: node.name,
                           subtitle: "\(HomeText.projectsIn(node.apps.count)) live in this folder. Each one runs, has git and a terminal of its own.",
                           illustration: .folders,
                           actions: [HeroAction(title: "Terminal here", systemImage: "terminal", style: .quiet) {
                               model.showTerminal(at: node.url, page: .folder(node.url.path))
                           }])

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: 520), spacing: 20)], spacing: 20) {
                    ForEach(node.children) { NodeCard(model: model, node: $0) }
                }
            }
            .padding(32)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.page = .home } label: { Label("Projects", systemImage: "chevron.left") }
                    .help("Back to projects")
            }
        }
        .navigationTitle(node.name)
    }
}
