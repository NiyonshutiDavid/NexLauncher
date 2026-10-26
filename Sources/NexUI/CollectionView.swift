import SwiftUI
import NexCore

struct CollectionView: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    let node: ProjectNode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    IconTile(name: node.name, glyph: "folder.fill", size: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(node.name).font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(theme.fg)
                        Text("Collection · \(HomeText.projectsIn(node.apps.count))").foregroundStyle(theme.fg2)
                    }
                    Spacer()
                    IconButton("terminal", help: "Open a terminal in this folder") { model.showTerminal(at: node.url, page: .folder(node.url.path)) }
                }

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
