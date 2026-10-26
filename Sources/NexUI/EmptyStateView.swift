import SwiftUI

struct EmptyStateView: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    let kind: EmptyStateKind

    var body: some View {
        VStack(spacing: 14) {
            IllustrationView(kind == .noProjects ? .folders : .telescope).frame(width: 180, height: 180)
            Text(kind == .noProjects ? "Nothing here yet" : "No matches").font(.title2.weight(.bold)).foregroundStyle(theme.fg)
            Text(kind == .noProjects
                 ? "No projects in \(model.settings.settings.scanRoot.path). Add one, clone a repository, or point NexLauncher at another folder."
                 : "Try a different search or filter.")
                .multilineTextAlignment(.center).foregroundStyle(theme.fg2).frame(maxWidth: 420)
            if kind == .noProjects {
                HStack(spacing: 10) {
                    Pill("Add project") { model.sheet = .addProject(.newFolder) }
                    Pill("Clone repository", style: .quiet) { model.sheet = .addProject(.clone) }
                    Pill("Choose folder", style: .quiet) { model.page = .settings(.general) }
                }
            } else {
                Pill("Clear filters", style: .quiet) { model.searchText = ""; model.select(filter: .all) }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}
