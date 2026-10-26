import SwiftUI
import NexCore

/// Compact pinned projects at the top of Home (hidden while another filter is active).
struct PinnedShelf: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let pinned = model.pinnedProjects
        if !pinned.isEmpty && model.filter == .all && !model.isFiltering {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Pinned")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(pinned) { project in
                            CardSurface {
                                HStack(spacing: 12) {
                                    IconTile(name: project.name, glyph: ProjectGlyph.symbol(for: project), size: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(project.name).font(.callout.weight(.semibold)).foregroundStyle(theme.fg).lineLimit(1)
                                        Text(ProjectSubtitle.text(for: project)).font(.caption).foregroundStyle(theme.fg2).lineLimit(1)
                                    }
                                    Spacer(minLength: 10)
                                    RunPill(model: model, project: project)
                                }
                                .padding(14)
                            }
                            .frame(width: 340)
                            .onTapGesture { model.page = .project(project.id); model.detailTab = .overview }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollClipDisabled()
            }
        }
    }
}
