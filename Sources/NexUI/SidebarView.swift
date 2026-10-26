import SwiftUI
import NexCore

struct SidebarView: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    private func count(_ f: ProjectFilter) -> Int {
        switch f {
        case .all: return model.projects.count
        case .pinned: return model.pinnedProjects.count
        case .running: return model.projects.filter { model.isRunning($0) }.count
        case .fullStack: return model.projects.filter(\.isFullStack).count
        case .flutter: return model.projects.filter { $0.targets.contains { $0.kind == .flutter } }.count
        }
    }

    private func isSelected(_ f: ProjectFilter) -> Bool {
        model.page == .home && model.filter == f && !model.showOnlyUncommitted
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.horizontal.circle.fill").foregroundStyle(theme.accent).font(.title3)
                        Text("NexLauncher").font(.headline.weight(.bold)).foregroundStyle(theme.fg)
                    }
                    .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 14)

                    ForEach(ProjectFilter.allCases) { f in
                        Button { model.select(filter: f) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: f.symbol).frame(width: 20)
                                Text(f.rawValue).font(.callout.weight(.medium))
                                Spacer()
                                let n = count(f)
                                if n > 0 { Text("\(n)").font(.caption.weight(.semibold)).foregroundStyle(theme.fg3) }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .foregroundStyle(isSelected(f) ? theme.accent : theme.fg)
                            .background(isSelected(f) ? theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }
            Divider().overlay(theme.line)
            ProfileRow(model: model)
        }
    }
}

struct ProfileRow: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    private var selected: Bool { if case .settings = model.page { return true } else { return false } }

    var body: some View {
        Button { model.page = .settings(.profile) } label: {
            HStack(spacing: 10) {
                ProfileAvatar(settings: model.settings.settings, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.settings.settings.displayName).font(.callout.weight(.semibold)).foregroundStyle(theme.fg).lineLimit(1)
                    Text("Settings").font(.caption).foregroundStyle(theme.fg2)
                }
                Spacer()
                Image(systemName: "gearshape").foregroundStyle(theme.fg3)
            }
            .padding(10)
            .background(selected ? theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(10)
        .help("Profile and settings")
    }
}
