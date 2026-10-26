import Foundation
import NexCore
import NexGit
import NexTerminal

public enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case profile = "Profile", git = "Git", appearance = "Appearance", general = "General", projects = "Projects"
    public var id: String { rawValue }
}

public enum AppPage: Equatable, Sendable {
    case home
    case settings(SettingsSection)
    case collection(String)      // ProjectNode id
    case project(String)         // Project id
    case folder(String)          // any folder (e.g. a new project with no manifests yet)
}

public enum AddProjectMode: Equatable, Sendable { case newFolder, clone }

public enum AppSheet: Identifiable, Equatable, Sendable {
    case addProject(AddProjectMode)
    case widgetsHowTo

    public var id: String {
        switch self {
        case .addProject(let mode): return "add-\(mode)"
        case .widgetsHowTo: return "widgets"
        }
    }
}

extension AppModel {
    // MARK: - View mode

    public var viewMode: ViewMode {
        get { settings.settings.viewMode }
        set { settings.settings.viewMode = newValue; settings.save() }
    }

    // MARK: - Terminal

    public func openTerminal(at url: URL) {
        terminals.open(at: url)
    }

    // MARK: - CTAs

    public var ctaContext: CTAContext {
        let lastName = settings.settings.lastRun.flatMap { run in projects.first { $0.id == run.projectID }?.name }
        return CTAContext(
            gitIdentitySet: gitIdentitySet,
            projectsWithChanges: gitBadges.values.filter { $0.changes > 0 }.count,
            lastRunName: lastName,
            anythingRunning: processes.runningCount > 0,
            themeChanged: settings.settings.theme != .ember || settings.settings.appearance != .system,
            widgetsConfirmed: settings.settings.widgetsConfirmed,
            launchAtLogin: login.isEnabled)
    }

    public var visibleCTAs: [CTA] {
        CTAEngine.visible(ctaContext, dismissed: settings.settings.dismissedCTAs)
    }

    public func dismiss(_ cta: CTAID) {
        settings.settings.dismissedCTAs.insert(cta.rawValue)
        settings.save()
    }

    public func resetTips() {
        settings.settings.dismissedCTAs = []
        settings.save()
    }

    public func perform(_ cta: CTAID) async {
        switch cta {
        case .addProject: sheet = .addProject(.newFolder)
        case .gitIdentity: page = .settings(.git)
        case .uncommitted:
            page = .home
            filter = .all
            showOnlyUncommitted = true
        case .resume:
            guard let last = settings.settings.lastRun,
                  let project = projects.first(where: { $0.id == last.projectID }),
                  let action = RunAction(rawValue: last.action) else { return }
            await run(project, kinds: action.kinds)
        case .themes: page = .settings(.appearance)
        case .widgets: sheet = .widgetsHowTo
        case .login: login.set(true)
        }
    }

    public func confirmWidgetsAdded() {
        settings.settings.widgetsConfirmed = true
        settings.save()
    }

    // MARK: - Git identity

    public func refreshGitIdentity() async {
        let identity = try? await git.identity(AppSettings.realHome, scope: .global)
        gitIdentitySet = identity?.name != nil && identity?.email != nil
    }

    // MARK: - Adding projects

    @discardableResult
    public func createProject(name: String, in parent: URL, initGit: Bool) async throws -> URL {
        let url = try await ProjectCreator(git: git).createFolder(
            name: name, in: parent, initGit: initGit, defaultBranch: settings.settings.defaultBranch)
        await finishAdding(url)
        return url
    }

    @discardableResult
    public func cloneProject(url: String, name: String, in parent: URL, onLine: @escaping @Sendable (String) -> Void) async throws -> URL {
        let folder = try await ProjectCreator(git: git).clone(url: url, name: name, in: parent, onLine: onLine)
        await finishAdding(folder)
        return folder
    }

    private func finishAdding(_ folder: URL) async {
        await refresh()
        let real = String(cString: realpath(folder.path, nil) ?? strdup(folder.path))
        if let project = projects.first(where: { $0.id == real || $0.id == folder.path }) {
            page = .project(project.id)
        } else {
            page = .folder(folder.path)
        }
    }
}

// MARK: - Home content

public enum EmptyStateKind: Equatable, Sendable { case noProjects, noResults }

public enum DetailTab: String, CaseIterable, Identifiable, Sendable {
    case overview = "Overview", terminal = "Terminal", logs = "Logs", git = "Git", files = "Files"
    public var id: String { rawValue }
}

public enum HomeItem: Identifiable {
    case project(Project)
    case collection(ProjectNode)

    public var id: String {
        switch self {
        case .project(let p): return p.id
        case .collection(let n): return n.id
        }
    }
}

public enum HomeText {
    public static func appsInside(_ n: Int) -> String { n == 1 ? "1 app inside" : "\(n) apps inside" }
    public static func projectsIn(_ n: Int) -> String { n == 1 ? "1 project" : "\(n) projects" }
}

public enum CardPrimaryAction {
    /// What the main pill does: prefers running everything, then frontend, backend, Flutter, Docker.
    public static func defaultAction(for actions: [RunAction]) -> RunAction? {
        [RunAction.both, .frontend, .backend, .flutter, .docker].first { actions.contains($0) }
    }

    public static func title(running: Bool, actions: [RunAction]) -> String {
        if running { return "Stop" }
        guard let action = defaultAction(for: actions) else { return "Run" }
        return actions.count > 1 ? "Run \(action.rawValue)" : "Run"
    }
}

extension AppModel {
    public func select(filter newFilter: ProjectFilter) {
        page = .home
        filter = newFilter
        showOnlyUncommitted = false
    }

    /// Top-level items for Home: apps and collections as on disk, or a flat filtered list while filtering or searching.
    public var homeItems: [HomeItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if filter == .all && query.isEmpty && !showOnlyUncommitted {
            return tree.map { node in
                if node.kind == .collection { return .collection(node) }
                return .project(node.project!)
            }
        }
        return filteredProjects.map { .project($0) }
    }

    public var emptyState: EmptyStateKind? {
        if projects.isEmpty { return isScanning ? nil : .noProjects }
        return homeItems.isEmpty ? .noResults : nil
    }

    public func node(id: String) -> ProjectNode? {
        func search(_ nodes: [ProjectNode]) -> ProjectNode? {
            for n in nodes {
                if n.id == id { return n }
                if let hit = search(n.children) { return hit }
            }
            return nil
        }
        return search(tree)
    }

    public func project(id: String) -> Project? { projects.first { $0.id == id } }

    /// Opens a terminal tab at `url` and shows the Terminal tab of `page`.
    public func showTerminal(at url: URL, page target: AppPage) {
        terminals.open(at: url)
        page = target
        detailTab = .terminal
    }

    public func setTheme(_ theme: ThemeID) { settings.settings.theme = theme; settings.save() }
    public func setAppearance(_ mode: AppearanceMode) { settings.settings.appearance = mode; settings.save() }
}

// MARK: - Git settings

public struct GitSettingsSnapshot: Equatable, Sendable {
    public var name: String?
    public var email: String?
    public var defaultBranch: String?
    public var credentialHelper: String?
}

extension AppModel {
    public func loadGitSettings() async -> GitSettingsSnapshot {
        let identity = try? await git.identity(AppSettings.realHome, scope: .global)
        return GitSettingsSnapshot(
            name: identity?.name, email: identity?.email,
            defaultBranch: await git.globalConfigValue("init.defaultBranch"),
            credentialHelper: await git.effectiveConfigValue("credential.helper"))
    }

    public func saveGitIdentity(name: String, email: String) async throws {
        try await git.setIdentity(GitIdentity(name: name, email: email), repo: AppSettings.realHome, scope: .global)
        await refreshGitIdentity()
    }

    public func saveDefaultBranch(_ branch: String) async throws {
        let value = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("-"), !value.contains(" ") else { throw ProjectCreationError.invalidBranch }
        try await git.setGlobalConfig("init.defaultBranch", value: value)
        settings.settings.defaultBranch = value
        settings.save()
    }
}
