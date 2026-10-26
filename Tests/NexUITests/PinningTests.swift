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

@MainActor
@Suite(.serialized) struct ToggleRunTests {
    private func waitUntil(_ timeout: TimeInterval = 5, _ cond: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if cond() { return true }; try? await Task.sleep(for: .milliseconds(25)) }
        return cond()
    }

    @Test func flutterOnlyProjectOpensItsPageInsteadOfSilentlyDoingNothing() async {
        let sb = Sandbox(); defer { _ = sb }
        sb.write("Mob/pubspec.yaml", "name: a\ndependencies:\n  flutter:\n    sdk: flutter\n")
        let m = sb.makeModel(); m.reloadWidgets = {}
        var opened = false
        m.openMainWindowAction = { opened = true }
        await m.refresh()
        await m.toggleRun(m.projects[0])
        #expect(m.page == .project(m.projects[0].id))
        #expect(opened)
        #expect(m.processes.runningCount == 0)
    }

    @Test func flutterPlusDockerRunsDocker() async {
        let sb = Sandbox(); defer { _ = sb }
        sb.write("Both/pubspec.yaml", "name: a\ndependencies:\n  flutter:\n    sdk: flutter\n")
        sb.write("Both/docker-compose.yml", "services: {}")
        let m = sb.makeModel(); m.reloadWidgets = {}
        await m.refresh()
        let docker = m.projects[0].targets.first { $0.kind == .docker }!
        m.overrides.set(Override(command: "sleep 30"), forPath: OverrideStore.key(directory: docker.directory, kind: .docker))
        await m.refresh()
        await m.toggleRun(m.projects[0])
        #expect(await waitUntil { m.processes.runningCount == 1 })
        await m.stopAllServices()
    }

    @Test func runningNeedingAnInstallBringsTheWindowForward() async {
        let sb = Sandbox(); defer { _ = sb }
        sb.write("Site/package.json", Sandbox.vite)                 // no node_modules
        let m = sb.makeModel(); m.reloadWidgets = {}
        var opened = false
        m.openMainWindowAction = { opened = true }
        await m.refresh()
        await m.toggleRun(m.projects[0])
        #expect(m.pendingInstall != nil)
        #expect(opened)
    }
}
