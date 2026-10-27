import Foundation
import Adwaita
import NexApp
import NexCore

/// The same sections as the Mac sidebar.
enum SidebarItem: String, CaseIterable, Identifiable {
    case all = "All Projects", pinned = "Pinned", running = "Running", fullStack = "Full-stack", flutter = "Flutter"
    case tasks = "Tasks", ai = "AI Assistant", settings = "Settings"
    var id: String { rawValue }

    var filter: ProjectFilter? {
        switch self {
        case .all: return .all
        case .pinned: return .pinned
        case .running: return .running
        case .fullStack: return .fullStack
        case .flutter: return .flutter
        default: return nil
        }
    }

    @MainActor
    static func current(_ model: AppModel) -> SidebarItem {
        switch model.page {
        case .tasks: return .tasks
        case .ai: return .ai
        case .settings: return .settings
        default:
            return allCases.first { $0.filter == model.filter } ?? .all
        }
    }

    @MainActor
    func select(in model: AppModel) {
        switch self {
        case .tasks: model.page = .tasks
        case .ai: model.page = .ai
        case .settings: model.page = .settings(.profile)
        default: if let filter { model.select(filter: filter) }
        }
    }

    /// Count shown beside the section, as on the Mac.
    @MainActor
    func count(_ model: AppModel) -> Int? {
        switch self {
        case .all: return model.projects.count
        case .pinned: return model.pinnedProjects.count
        case .running: return model.projects.filter { model.isRunning($0) }.count
        case .fullStack: return model.projects.filter(\.isFullStack).count
        case .flutter: return model.projects.filter { $0.targets.contains { $0.kind == .flutter } }.count
        case .tasks: return model.tasks.filter { !$0.isDone }.count
        default: return nil
        }
    }
}

struct Sidebar: View {
    let model: AppModel

    var view: Body {
        ScrollView {
            List(SidebarItem.allCases, selection: Binding(get: { SidebarItem.current(model).id },
                                                          set: { id in SidebarItem(rawValue: id)?.select(in: model) })) { item in
                HStack {
                    Text(item.rawValue).halign(.start).hexpand()
                    if let n = item.count(model), n > 0 { Text("\(n)").style("dim-label") }
                }
                .padding(10)
            }
            .sidebarStyle()
        }
        .hscrollbarPolicy(.never)
        .topToolbar {
            HeaderBar.end {}
                .headerBarTitle { WindowTitle(subtitle: "", title: "NexLauncher") }
        }
    }
}
