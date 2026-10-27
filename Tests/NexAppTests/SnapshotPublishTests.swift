import Testing
import Foundation
import NexCore
@testable import NexApp
import NexTestSupport

@MainActor
@Suite(.serialized) struct SnapshotPublishTests {
    private func setup() async -> (Sandbox, AppModel, Project) {
        let sb = Sandbox()
        sb.write("Site/package.json", Sandbox.vite)
        try! FileManager.default.createDirectory(at: sb.scanRoot.appendingPathComponent("Site/node_modules"), withIntermediateDirectories: true)
        let model = sb.makeModel()
        model.reloadWidgets = {}
        await model.refresh()
        let dir = model.projects[0].targets[0].directory
        model.overrides.set(Override(command: "echo 'ready http://localhost:7777'; sleep 30", port: nil),
                            forPath: OverrideStore.key(directory: dir, kind: .frontend))
        await model.refresh()
        return (sb, model, model.projects[0])
    }

    private func waitUntil(_ cond: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(5)
        while Date() < end { if cond() { return true }; try? await Task.sleep(for: .milliseconds(25)) }
        return cond()
    }

    @Test func modelPublishesSnapshotWhenServiceStarts() async {
        let (sb, model, project) = await setup()
        await model.run(project, kinds: [.frontend])
        let dir = sb.root.appendingPathComponent("shared")
        #expect(await waitUntil { SharedContainer.read(from: dir).running.first?.port == 7777 })
        let running = SharedContainer.read(from: dir).running
        #expect(running.first?.projectName == "Site")
        #expect(running.first?.kind == .frontend)
        await model.stopAllServices()
        #expect(await waitUntil { SharedContainer.read(from: dir).running.isEmpty })
    }

    @Test func snapshotIncludesPinnedProjects() async {
        let (sb, model, project) = await setup()
        model.settings.settings.pinnedProjectIDs = [project.id]
        model.publishSnapshot()
        let pinned = SharedContainer.read(from: sb.root.appendingPathComponent("shared")).pinned
        #expect(pinned == [.init(id: project.id, name: "Site")])
    }

    @Test func widgetsAreToldToReloadOnPublish() async {
        let (sb, model, _) = await setup()
        defer { _ = sb }
        var reloads = 0
        model.reloadWidgets = { reloads += 1 }
        model.publishSnapshot()
        #expect(reloads == 1)
    }

    @Test func runURLStartsDefaultAction() async {
        let (sb, model, project) = await setup()
        defer { _ = sb }
        var comps = URLComponents(string: "nexlauncher://run")!
        comps.queryItems = [URLQueryItem(name: "project", value: project.id)]
        await model.handle(url: comps.url!)
        #expect(await waitUntil { model.isRunning(project) })
        await model.stopAllServices()
    }

    @Test func unknownProjectURLIsIgnored() async {
        let (sb, model, _) = await setup()
        defer { _ = sb }
        await model.handle(url: URL(string: "nexlauncher://run?project=%2Fnope")!)
        #expect(model.processes.runningCount == 0)
        await model.handle(url: URL(string: "https://example.com")!)
        #expect(model.processes.runningCount == 0)
    }

    @Test func urlArrivingBeforeFirstScanIsQueuedNotDropped() async {
        let sb = Sandbox()
        defer { _ = sb }
        sb.write("Site/package.json", Sandbox.vite)
        try! FileManager.default.createDirectory(at: sb.scanRoot.appendingPathComponent("Site/node_modules"), withIntermediateDirectories: true)
        let model = sb.makeModel()
        model.reloadWidgets = {}
        model.overrides.set(Override(command: "sleep 30"), forPath: OverrideStore.key(directory: sb.scanRoot.appendingPathComponent("Site"), kind: .frontend))
        let id = String(cString: realpath(sb.scanRoot.appendingPathComponent("Site").path, nil))   // the scanner reports real paths
        var comps = URLComponents(string: "nexlauncher://run")!
        comps.queryItems = [URLQueryItem(name: "project", value: id)]
        await model.handle(url: comps.url!)           // no projects yet
        #expect(model.processes.runningCount == 0)
        await model.refresh()
        #expect(await waitUntil { model.processes.runningCount == 1 })
        await model.stopAllServices()
    }
}
