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
