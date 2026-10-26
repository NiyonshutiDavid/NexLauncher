import Foundation
import Observation
import NexCore
import NexProcess
import NexGit

public struct GitBadge: Equatable, Sendable {
    public var changes = 0, ahead = 0, behind = 0, repoCount = 0
    public var isClean: Bool { changes == 0 && ahead == 0 && behind == 0 }
}

public enum ProjectFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All Projects", fullStack = "Full-stack", running = "Running", flutter = "Flutter"
    public var id: String { rawValue }
    public var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .fullStack: return "rectangle.on.rectangle"
        case .running: return "play.circle"
        case .flutter: return "iphone"
        }
    }
}

@MainActor @Observable
public final class AppModel {
    public private(set) var projects: [Project] = []
    public private(set) var isScanning = false
    public var searchText = ""
    public var filter: ProjectFilter = .all
    public private(set) var gitBadges: [String: GitBadge] = [:]
    public var pendingInstall: PendingInstall?
    /// Test seam: replaces `npm install`.
    var installCommandOverride: String?

    public let settings: SettingsStore
    public let overrides: OverrideStore
    public let processes: ProcessManager
    public let git: GitService
    let snapshotDirectory: URL

    public init(settings: SettingsStore? = nil,
                overrides: OverrideStore? = nil,
                processes: ProcessManager? = nil,
                git: GitService = GitService(),
                snapshotDirectory: URL? = nil) {
        self.settings = settings ?? SettingsStore()
        self.overrides = overrides ?? OverrideStore(fileURL: AppSettings.supportDirectory.appendingPathComponent("overrides.json"))
        self.processes = processes ?? ProcessManager()
        self.git = git
        self.snapshotDirectory = snapshotDirectory ?? SharedContainer.defaultDirectory
    }

    public var greeting: String {
        Greeter.greeting(for: Date(), name: settings.settings.displayName)
    }

    public var filteredProjects: [Project] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return projects.filter { project in
            switch filter {
            case .all: break
            case .fullStack: guard project.isFullStack else { return false }
            case .flutter: guard project.targets.contains(where: { $0.kind == .flutter }) else { return false }
            case .running: guard isRunning(project) else { return false }
            }
            return query.isEmpty || project.name.localizedCaseInsensitiveContains(query)
        }
    }

    public func isRunning(_ project: Project) -> Bool {
        processes.states.contains { $0.key.projectID == project.id && $0.value.isActive }
    }

    public func refresh() async {
        isScanning = true
        defer { isScanning = false }
        let root = settings.settings.scanRoot
        let scanner = ProjectScanner(overrides: overrides)
        projects = await Task.detached { scanner.scan(root: root) }.value
        Task { await refreshGitBadges() }
    }

    /// Summarises each project's repositories (change count, ahead/behind) for the card badges.
    public func refreshGitBadges() async {
        var badges: [String: GitBadge] = [:]
        for project in projects {
            let repos = git.findRepos(under: project.root)
            guard !repos.isEmpty else { continue }
            var badge = GitBadge(repoCount: repos.count)
            for repo in repos {
                guard let s = try? await git.status(repo) else { continue }
                badge.changes += s.changes.count
                badge.ahead += s.ahead
                badge.behind += s.behind
            }
            badges[project.id] = badge
        }
        gitBadges = badges
    }
}

extension AppModel {
    /// Publishes running/pinned state for the widgets. Filled in by the widget task.
    func publishSnapshot() {}
}

extension AppModel {
    /// Text shown beside the menu bar icon: the number of running services, or nothing.
    public var menuBarTitle: String {
        processes.runningCount > 0 ? "\(processes.runningCount)" : ""
    }

    public var shouldConfirmQuit: Bool { processes.runningCount > 0 }
}

import AppKit
extension AppModel {
    /// Shows or hides the Dock icon according to settings (the menu bar item always stays).
    public func applyDockIconPolicy() {
        NSApp.setActivationPolicy(settings.settings.showDockIcon ? .regular : .accessory)
    }
}
