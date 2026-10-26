import Testing
import Foundation
import NexCore
@testable import NexUI

@MainActor
@Suite struct UIStateTests {
    private let flutter = "name: a\ndependencies:\n  flutter:\n    sdk: flutter\n"

    @Test func selectingSidebarFilterGoesHomeAndClearsUncommittedFilter() {
        let model = Sandbox().makeModel()
        model.page = .settings(.git)
        model.showOnlyUncommitted = true
        model.select(filter: .running)
        #expect(model.page == .home && model.filter == .running && !model.showOnlyUncommitted)
    }

    @Test func emptyStateDistinguishesNoProjectsFromNoResults() async {
        let sb = Sandbox()
        let empty = sb.makeModel(); empty.reloadWidgets = {}
        await empty.refresh()
        #expect(empty.emptyState == .noProjects)
        sb.write("Site/package.json", Sandbox.vite)
        await empty.refresh()
        #expect(empty.emptyState == nil)
        empty.searchText = "zzz"
        #expect(empty.emptyState == .noResults)
    }

    @Test func appsInsideChipTextSingularAndPlural() {
        #expect(HomeText.appsInside(1) == "1 app inside")
        #expect(HomeText.appsInside(3) == "3 apps inside")
        #expect(HomeText.projectsIn(2) == "2 projects")
        #expect(HomeText.projectsIn(1) == "1 project")
    }

    @Test func cardPrimaryActionTitle() {
        #expect(CardPrimaryAction.title(running: true, actions: [.frontend]) == "Stop")
        #expect(CardPrimaryAction.title(running: false, actions: [.frontend]) == "Run")
        #expect(CardPrimaryAction.title(running: false, actions: [.frontend, .backend, .both]) == "Run Both")
        #expect(CardPrimaryAction.title(running: false, actions: [.frontend, .flutter]) == "Run Frontend")
        #expect(CardPrimaryAction.defaultAction(for: [.flutter, .docker]) == .flutter)
        #expect(CardPrimaryAction.defaultAction(for: []) == nil)
    }

    @Test func homeItemsGroupCollectionsAndFlattenWhenFiltering() async {
        let sb = Sandbox()
        sb.write("intern/a/pubspec.yaml", flutter); sb.write("intern/b/pubspec.yaml", flutter)
        sb.write("Site/package.json", Sandbox.vite)
        let model = sb.makeModel(); model.reloadWidgets = {}
        await model.refresh()
        #expect(model.homeItems.count == 2)
        #expect(model.homeItems.contains { if case .collection(let n) = $0 { return n.name == "intern" } else { return false } })
        model.filter = .flutter
        #expect(model.homeItems.count == 2)             // flat: the two flutter apps
        #expect(model.homeItems.allSatisfy { if case .project = $0 { return true } else { return false } })
        model.filter = .all
        model.searchText = "site"
        #expect(model.homeItems.count == 1)
    }

    @Test func nodeLookupFindsNestedNodes() async {
        let sb = Sandbox()
        sb.write("sessions/week1/a/pubspec.yaml", flutter); sb.write("sessions/week2/a/pubspec.yaml", flutter)
        let model = sb.makeModel(); model.reloadWidgets = {}
        await model.refresh()
        let week1 = model.tree[0].children[0]
        #expect(model.node(id: week1.id)?.name == "week1")
        #expect(model.node(id: "/nope") == nil)
    }

    @Test func showTerminalOpensTabAndSelectsTerminalTab() {
        let sb = Sandbox()
        sb.write("Site/package.json", Sandbox.vite)
        let model = sb.makeModel()
        let dir = sb.scanRoot.appendingPathComponent("Site")
        model.showTerminal(at: dir, page: .project(dir.path))
        #expect(model.page == .project(dir.path) && model.detailTab == .terminal)
        #expect(model.terminals.sessions.count == 1)
        model.terminals.closeAll()
    }

    @Test func themeAndAppearanceChangesPersist() {
        let sb = Sandbox()
        let model = sb.makeModel()
        model.setTheme(.violet); model.setAppearance(.dark)
        let saved = SettingsStore(fileURL: sb.root.appendingPathComponent("settings.json")).settings
        #expect(saved.theme == .violet && saved.appearance == .dark)
    }
}
