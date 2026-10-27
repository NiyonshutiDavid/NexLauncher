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
}
