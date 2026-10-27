import Testing
import Foundation
import NexApp
import NexCore
import NexTestSupport
@testable import NexLinux

/// Builds each Linux page's description (no window needed) so a crash in a view body shows up in CI.
@MainActor
@Suite(.serialized) struct LinuxViewSmokeTests {
    @Test func homeBuildsForEveryEmptyState() async {
        let sb = Sandbox()
        let empty = sb.makeModel()
        empty.reloadWidgets = {}
        await empty.refresh()
        #expect(empty.emptyState == .noProjects)
        _ = HomePage(model: empty).view

        sb.write("Site/package.json", Sandbox.vite)
        sb.write("sessions/week1/app/pubspec.yaml", "name: a\ndependencies:\n  flutter:\n    sdk: flutter")
        sb.write("sessions/week2/app/pubspec.yaml", "name: b\ndependencies:\n  flutter:\n    sdk: flutter")
        let model = sb.makeModel()
        model.reloadWidgets = {}
        await model.refresh()
        _ = HomePage(model: model).view
        model.searchText = "zzz-nothing"
        #expect(model.emptyState == .noResults)
        _ = HomePage(model: model).view
        model.searchText = ""
        model.page = .collection(model.tree.first { $0.kind == .collection }!.id)
        _ = ContentRouter(model: model).view
    }

    @Test func projectPageEveryTab() async {
        let sb = Sandbox()
        sb.write("Site/package.json", Sandbox.vite)
        let model = sb.makeModel()
        model.reloadWidgets = {}
        await model.refresh()
        let project = model.projects[0]
        model.page = .project(project.id)
        for tab in DetailTab.allCases {
            model.detailTab = tab
            _ = ProjectPage(model: model, project: project).view
        }
        model.setup = SetupSession(project: project, steps: [])
        _ = SetupDialogContent(model: model).view
        _ = AddProjectDialogContent(model: model, mode: .clone).view
    }

    @Test func gitPanelWithoutRepo() {
        let sb = Sandbox()
        let model = sb.makeModel()
        _ = GitPanel(model: model, repo: sb.root).view
    }

    @Test func tasksPageEmpty() {
        let model = Sandbox().makeModel()
        model.page = .tasks
        _ = ContentRouter(model: model).view
        _ = DevicesSection(model: model).view
    }

    @Test func aiPageAndPanel() async {
        let sb = Sandbox()
        sb.write("Site/package.json", Sandbox.vite)
        let model = sb.makeModel()
        model.reloadWidgets = {}
        await model.refresh()
        model.page = .ai
        _ = ContentRouter(model: model).view
        model.aiPanelProjectID = model.projects[0].id
        _ = ProjectPage(model: model, project: model.projects[0]).view
    }

    @Test func settingsAndOnboarding() {
        let model = Sandbox().makeModel()
        model.page = .settings(.profile)
        _ = ContentRouter(model: model).view
        _ = OnboardingContent(model: model).view
    }
}
