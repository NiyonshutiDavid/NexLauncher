import Testing
import Foundation
import NexCore
@testable import NexUI

@MainActor
@Suite struct PinningTests {
    private func models() async -> (Sandbox, AppModel) {
        let sb = Sandbox()
        for n in ["Alpha", "Beta", "Gamma"] { sb.write("\(n)/package.json", Sandbox.vite) }
        let m = sb.makeModel(); m.reloadWidgets = {}
        await m.refresh()
        return (sb, m)
    }

    @Test func togglePinAddsRemovesAndPersists() async {
        let (sb, m) = await models(); defer { _ = sb }
        let alpha = m.projects[0]
        #expect(!m.isPinned(alpha))
        m.togglePin(alpha)
        #expect(m.isPinned(alpha))
        #expect(SettingsStore(fileURL: sb.root.appendingPathComponent("settings.json")).settings.pinnedProjectIDs == [alpha.id])
        m.togglePin(alpha)
        #expect(!m.isPinned(alpha))
    }

    @Test func pinnedProjectsKeepPinOrderAndIgnoreStaleIds() async {
        let (sb, m) = await models(); defer { _ = sb }
        m.togglePin(m.projects[2]); m.togglePin(m.projects[0])
        m.settings.settings.pinnedProjectIDs.append("/gone/project")
        #expect(m.pinnedProjects.map(\.name) == ["Gamma", "Alpha"])
    }

    @Test func pinnedFilterShowsOnlyPinnedProjects() async {
        let (sb, m) = await models(); defer { _ = sb }
        m.togglePin(m.projects[1])
        m.select(filter: .pinned)
        #expect(m.homeItems.count == 1)
        #expect(m.filteredProjects.map(\.name) == ["Beta"])
    }

    @Test func pinningPublishesToTheWidgetSnapshot() async {
        let (sb, m) = await models(); defer { _ = sb }
        m.togglePin(m.projects[0])
        let pinned = SharedContainer.read(from: sb.root.appendingPathComponent("shared")).pinned
        #expect(pinned.map(\.name) == ["Alpha"])
    }

    @Test func dockMenuEntriesShowRunOrStopPerPinnedProject() async {
        let (sb, m) = await models(); defer { _ = sb }
        let a = m.projects[0], b = m.projects[1]
        let entries = PinnedMenu.entries(pinned: [a, b], isRunning: { $0.id == b.id })
        #expect(entries.map(\.title) == ["Run Alpha", "Stop Beta"])
        #expect(entries.map(\.isRunning) == [false, true])
        #expect(PinnedMenu.entries(pinned: [], isRunning: { _ in false }).isEmpty)
    }

    @Test func sidebarHasAPinnedItem() {
        #expect(ProjectFilter.allCases.map(\.rawValue).contains("Pinned"))
        #expect(ProjectFilter.pinned.symbol == "pin")
    }
}
