import Foundation
import NexCore

public struct PinnedEntry: Identifiable, Equatable, Sendable {
    public let id: String          // project id
    public let title: String       // "Run Alpha" / "Stop Alpha"
    public let isRunning: Bool
}

/// What the Dock menu (and any other quick list) shows for pinned projects.
public enum PinnedMenu {
    public static func entries(pinned: [Project], isRunning: (Project) -> Bool) -> [PinnedEntry] {
        pinned.map { project in
            let running = isRunning(project)
            return PinnedEntry(id: project.id, title: (running ? "Stop " : "Run ") + project.name, isRunning: running)
        }
    }
}

extension AppModel {
    public func isPinned(_ project: Project) -> Bool {
        settings.settings.pinnedProjectIDs.contains(project.id)
    }

    /// Pinned projects in the order they were pinned; ids that no longer exist are ignored.
    public var pinnedProjects: [Project] {
        settings.settings.pinnedProjectIDs.compactMap { id in projects.first { $0.id == id } }
    }

    public func togglePin(_ project: Project) {
        var ids = settings.settings.pinnedProjectIDs.filter { $0 != project.id }
        if !isPinned(project) { ids.append(project.id) }
        settings.settings.pinnedProjectIDs = ids
        settings.save()
        publishSnapshot()           // the Quick Launch widget reads the same list
    }

    /// Run with the project's default action, or stop it if it is running (Dock menu, menu bar, URL).
    public func toggleRun(_ project: Project) async {
        if isRunning(project) { await stop(project); return }
        let actions = availableActions(for: project)
        guard let action = CardPrimaryAction.defaultAction(for: actions), action != .flutter else { return }
        await run(project, kinds: action.kinds)
    }
}
