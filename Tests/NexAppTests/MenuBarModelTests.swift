import Testing
import Foundation
import NexCore
@testable import NexApp
import NexTestSupport

@MainActor
@Suite(.serialized) struct MenuBarModelTests {
    private func startOne() async -> (Sandbox, AppModel, Project) {
        let sb = Sandbox()
        sb.write("Site/package.json", Sandbox.vite)
        try! FileManager.default.createDirectory(at: sb.scanRoot.appendingPathComponent("Site/node_modules"), withIntermediateDirectories: true)
        let model = sb.makeModel()
        await model.refresh()
        let p = model.projects[0]
        let dir = p.targets[0].directory
        model.overrides.set(Override(command: "sleep 30"), forPath: OverrideStore.key(directory: dir, kind: .frontend))
        await model.refresh()
        return (sb, model, model.projects[0])
    }

    @Test func menuBarTitleEmptyWhenNothingRuns() {
        let model = Sandbox().makeModel()
        #expect(model.menuBarTitle == "")
        #expect(!model.shouldConfirmQuit)
    }

    @Test func menuBarTitleReflectsRunningCount() async {
        let (sb, model, p) = await startOne()
        defer { _ = sb }
        await model.run(p, kinds: [.frontend])
        try? await Task.sleep(for: .milliseconds(200))
        #expect(model.menuBarTitle == "1")
        await model.stopAllServices()
        #expect(model.menuBarTitle == "")
    }

    @Test func confirmQuitOnlyWhenServicesRunning() async {
        let (sb, model, p) = await startOne()
        defer { _ = sb }
        #expect(!model.shouldConfirmQuit)
        await model.run(p, kinds: [.frontend])
        #expect(model.shouldConfirmQuit)
        await model.stopAllServices()
        #expect(!model.shouldConfirmQuit)
    }
}
