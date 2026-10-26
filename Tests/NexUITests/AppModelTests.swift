import Testing
import Foundation
import NexCore
@testable import NexUI

@MainActor
@Suite struct AppModelTests {
    @Test func refreshLoadsProjectsFromScanner() async {
        let sb = Sandbox()
        sb.write("Alpha/package.json", Sandbox.vite)
        sb.write("Beta/manage.py")
        let model = sb.makeModel()
        await model.refresh()
        #expect(model.projects.map(\.name) == ["Alpha", "Beta"])
    }

    @Test func searchFiltersByNameCaseInsensitively() async {
        let sb = Sandbox()
        sb.write("CleanPay/package.json", Sandbox.vite)
        sb.write("Jarama/package.json", Sandbox.vite)
        let model = sb.makeModel()
        await model.refresh()
        model.searchText = "clean"
        #expect(model.filteredProjects.map(\.name) == ["CleanPay"])
        model.searchText = ""
        #expect(model.filteredProjects.count == 2)
    }

    @Test func refreshWithMissingRootGivesEmptyListNotCrash() async {
        let model = Sandbox().makeModel()
        await model.refresh()
        #expect(model.projects.isEmpty)
        #expect(!model.isScanning)
    }

    @Test func greetingUsesDisplayName() {
        let model = Sandbox().makeModel()
        model.settings.settings.displayName = "David"
        #expect(model.greeting.hasSuffix(", David"))
    }
}

@MainActor
@Suite struct ProjectFilterTests {
    @Test func filterSelectsFullStackAndFlutter() async {
        let sb = Sandbox()
        sb.write("Full/frontend/package.json", Sandbox.vite)
        sb.write("Full/backend/manage.py")
        sb.write("Front/package.json", Sandbox.vite)
        sb.write("Mob/pubspec.yaml", "dependencies:\n  flutter:\n    sdk: flutter\n")
        let model = sb.makeModel()
        await model.refresh()
        model.filter = .fullStack
        #expect(model.filteredProjects.map(\.name) == ["Full"])
        model.filter = .flutter
        #expect(model.filteredProjects.map(\.name) == ["Mob"])
        model.filter = .all
        #expect(model.filteredProjects.count == 3)
    }
}
