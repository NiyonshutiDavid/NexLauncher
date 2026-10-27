import Testing
import Foundation
import NexCore
@testable import NexUI
import NexApp
import NexTestSupport

@Suite struct QuickPanelTests {
    private func p(_ name: String) -> Project {
        Project(id: "/p/\(name)", name: name, root: URL(fileURLWithPath: "/p/\(name)"), targets: [])
    }

    @Test func runningProjectsAreNotRepeatedUnderPinned() {
        let a = p("A"), b = p("B"), c = p("C")
        let s = QuickPanelSections(running: [b], pinned: [a, b, c])
        #expect(s.running.map(\.name) == ["B"])
        #expect(s.pinned.map(\.name) == ["A", "C"])
        #expect(!s.isEmpty)
    }

    @Test func emptyWhenNothingRunsAndNothingIsPinned() {
        #expect(QuickPanelSections(running: [], pinned: []).isEmpty)
    }

    @Test func listHeightGrowsWithRowsButIsCapped() {
        let one = QuickPanelSections(running: [p("A")], pinned: [])
        let many = QuickPanelSections(running: (0..<20).map { p("R\($0)") }, pinned: (0..<20).map { p("P\($0)") })
        #expect(one.listHeight > 0)
        #expect(many.listHeight == QuickPanelSections.maxListHeight)
        #expect(one.listHeight < many.listHeight)
    }
}

@Suite struct QuickPanelTaskTests {
    private func task(_ title: String, done: Bool = false) -> ProjectTask {
        ProjectTask(id: UUID(), projectID: "/p/A", projectName: "A", title: title, notes: "", createdAt: Date(), doneAt: done ? Date() : nil)
    }

    @Test func openTasksAreListedAndCapped() {
        let tasks = (1...9).map { task("T\($0)") } + [task("done", done: true)]
        let s = QuickPanelSections(running: [], pinned: [], tasks: tasks)
        #expect(s.tasks.count == QuickPanelSections.maxTasks)
        #expect(!s.tasks.contains { $0.isDone })
        #expect(s.moreTasks == 9 - QuickPanelSections.maxTasks)
        #expect(!s.isEmpty)
    }

    @Test func tasksAddToTheListHeight() {
        let without = QuickPanelSections(running: [], pinned: [], tasks: [])
        let with = QuickPanelSections(running: [], pinned: [], tasks: [task("a"), task("b")])
        #expect(without.isEmpty)
        #expect(with.listHeight > 0)
    }
}
