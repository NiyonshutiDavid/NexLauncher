import Testing
import Foundation
import NexCore
import NexTestSupport
@testable import NexUI

@MainActor
@Suite struct ProjectFilterSetTests {
    private let flutter = "name: a\ndependencies:\n  flutter:\n    sdk: flutter\n"

    /// Full (fullstack), Site (vite frontend), Api (django backend), sessions/{a,b} (flutter collection)
    private func model() async -> (Sandbox, AppModel) {
        let sb = Sandbox()
        sb.write("Full/frontend/package.json", Sandbox.vite); sb.write("Full/backend/manage.py")
        sb.write("Site/package.json", Sandbox.vite)
        sb.write("Api/manage.py")
        sb.write("sessions/a/pubspec.yaml", flutter); sb.write("sessions/b/pubspec.yaml", flutter)
        let m = sb.makeModel(); m.reloadWidgets = {}
        await m.refresh()
        return (sb, m)
    }
    private func names(_ m: AppModel) -> [String] {
        m.homeItems.map { item -> String in
            switch item {
            case .project(let p): return p.name
            case .collection(let n): return "[\(n.name)]"
            }
        }.sorted()
    }

    @Test func defaultShowsCollectionsAsCards() async {
        let (sb, m) = await model(); defer { _ = sb }
        #expect(names(m) == ["Api", "Full", "Site", "[sessions]"])
        #expect(!m.filters.isActive)
    }

    @Test func kindFilterKeepsOnlyMatchingProjectsIncludingThoseInCollections() async {
        let (sb, m) = await model(); defer { _ = sb }
        m.filters.kinds = [.flutter]
        #expect(names(m) == ["a", "b"])
        m.filters.kinds = [.fullStack]
        #expect(names(m) == ["Full"])
        m.filters.kinds = [.frontend, .backend]          // either
        #expect(names(m) == ["Api", "Full", "Site"])
    }

    @Test func frameworkFilter() async {
        let (sb, m) = await model(); defer { _ = sb }
        #expect(m.availableFrameworks.contains("Django") && m.availableFrameworks.contains("Vite") && m.availableFrameworks.contains("Flutter"))
        m.filters.frameworks = ["Django"]
        #expect(names(m) == ["Api", "Full"])
    }

    @Test func hidingCollectionsRemovesThemAndTheirApps() async {
        let (sb, m) = await model(); defer { _ = sb }
        m.filters.collections = .hide
        #expect(names(m) == ["Api", "Full", "Site"])
        m.filters.kinds = [.flutter]
        #expect(names(m).isEmpty)
    }

    @Test func onlyCollections() async {
        let (sb, m) = await model(); defer { _ = sb }
        m.filters.collections = .only
        #expect(names(m) == ["[sessions]"])
    }

    @Test func expandingCollectionsListsTheirAppsIndividually() async {
        let (sb, m) = await model(); defer { _ = sb }
        m.filters.collections = .expand
        #expect(names(m) == ["Api", "Full", "Site", "a", "b"])
    }

    @Test func gitFilterUsesBadges() async {
        let (sb, m) = await model(); defer { _ = sb }
        TempRepo(initialize: false).run(["init", "-b", "main"], in: sb.scanRoot.appendingPathComponent("Site"))
        await m.refreshGitBadges()
        m.filters.git = .changes
        #expect(names(m) == ["Site"])
        m.filters.git = .clean
        #expect(!names(m).contains("Site"))
    }

    @Test func clearingRestoresTheDefault() async {
        let (sb, m) = await model(); defer { _ = sb }
        m.filters.kinds = [.flutter]; m.filters.collections = .hide; m.filters.onlyPinned = true
        #expect(m.filters.activeCount == 3)
        m.clearFilters()
        #expect(!m.filters.isActive && names(m).count == 4)
    }
}

@MainActor
@Suite struct BreadcrumbTests {
    private let flutter = "name: a\ndependencies:\n  flutter:\n    sdk: flutter\n"

    @Test func nestedProjectShowsEveryLevel() async {
        let sb = Sandbox(); defer { _ = sb }
        sb.write("sessions/week1/app/pubspec.yaml", flutter); sb.write("sessions/week2/app/pubspec.yaml", flutter)
        let m = sb.makeModel(); m.reloadWidgets = {}
        await m.refresh()
        let sessions = m.tree[0], week1 = sessions.children[0]
        let crumbs = m.breadcrumbs(for: .project(week1.id))
        #expect(crumbs.map(\.title) == ["Projects", "sessions", "week1"])
        #expect(crumbs[0].page == .home && crumbs[1].page == .collection(sessions.id) && crumbs[2].page == nil)
    }

    @Test func backGoesUpOneLevel() async {
        let sb = Sandbox(); defer { _ = sb }
        sb.write("sessions/week1/app/pubspec.yaml", flutter); sb.write("sessions/week2/app/pubspec.yaml", flutter)
        let m = sb.makeModel(); m.reloadWidgets = {}
        await m.refresh()
        let sessions = m.tree[0], week1 = sessions.children[0]
        m.page = .project(week1.id)
        m.goBack()
        #expect(m.page == .collection(sessions.id))
        m.goBack()
        #expect(m.page == .home)
    }

    @Test func topLevelProject() async {
        let sb = Sandbox(); defer { _ = sb }
        sb.write("Site/package.json", Sandbox.vite)
        let m = sb.makeModel(); m.reloadWidgets = {}
        await m.refresh()
        #expect(m.breadcrumbs(for: .project(m.projects[0].id)).map(\.title) == ["Projects", "Site"])
    }

    @Test func folderPagesWalkTheFolders() async throws {
        let sb = Sandbox(); defer { _ = sb }
        sb.write("Site/package.json", Sandbox.vite)
        try FileManager.default.createDirectory(at: sb.scanRoot.appendingPathComponent("Site/docs/api"), withIntermediateDirectories: true)
        let m = sb.makeModel(); m.reloadWidgets = {}
        await m.refresh()
        let site = m.projects[0]
        let path = site.root.appendingPathComponent("docs/api").path
        let crumbs = m.breadcrumbs(for: .folder(path))
        #expect(crumbs.map(\.title) == ["Projects", "Site", "docs", "api"])
        #expect(crumbs[1].page == .project(site.id))
        #expect(crumbs[2].page == .folder(site.root.appendingPathComponent("docs").path))
    }
}

@MainActor
@Suite struct AIPanelTests {
    @Test func askAIInsideAProjectOpensThePanelInsteadOfNavigating() async {
        let sb = Sandbox(); defer { _ = sb }
        sb.write("Site/package.json", Sandbox.vite)
        let m = sb.makeModel(); m.reloadWidgets = {}
        await m.refresh()
        let p = m.projects[0]
        m.page = .project(p.id)
        let task = m.addTask(title: "Write tests", notes: "", project: p)!
        m.draftAgentTask(task, project: p)
        #expect(m.page == .project(p.id))
        #expect(m.aiPanelProjectID == p.id)
        #expect(m.agentDraft?.taskID == task.id)
    }

    @Test func askAIFromElsewhereStillOpensTheAIPage() async {
        let sb = Sandbox(); defer { _ = sb }
        sb.write("Site/package.json", Sandbox.vite)
        let m = sb.makeModel(); m.reloadWidgets = {}
        await m.refresh()
        let p = m.projects[0]
        m.page = .tasks
        m.draftAgentTask(m.addTask(title: "x", notes: "", project: p)!, project: p)
        #expect(m.page == .ai && m.aiPanelProjectID == nil)
    }

    @Test func togglingThePanel() async {
        let sb = Sandbox(); defer { _ = sb }
        sb.write("Site/package.json", Sandbox.vite)
        let m = sb.makeModel(); m.reloadWidgets = {}
        await m.refresh()
        let p = m.projects[0]
        m.toggleAIPanel(for: p)
        #expect(m.aiPanelProjectID == p.id)
        m.toggleAIPanel(for: p)
        #expect(m.aiPanelProjectID == nil)
    }

    @Test func runsForAProjectAreSeparated() async {
        let sb = Sandbox(); defer { _ = sb }
        sb.write("A/package.json", Sandbox.vite); sb.write("B/package.json", Sandbox.vite)
        let m = sb.makeModel(); m.reloadWidgets = {}
        m.settings.settings.customAgentCommand = #"echo "$NEX_TASK""#
        await m.refresh()
        let a = m.projects.first { $0.name == "A" }!, b = m.projects.first { $0.name == "B" }!
        _ = m.startAgent(.custom, task: "one", project: a); _ = m.startAgent(.custom, task: "two", project: b)
        #expect(m.agentRuns(for: a).map(\.task) == ["one"])
    }
}
