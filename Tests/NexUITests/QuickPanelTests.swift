import Testing
import Foundation
import NexCore
@testable import NexUI

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
