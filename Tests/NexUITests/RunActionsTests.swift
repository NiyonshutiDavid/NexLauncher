import Testing
import Foundation
import NexCore
import NexProcess
@testable import NexUI

@MainActor
@Suite(.serialized) struct RunActionsTests {
    private func waitUntil(_ timeout: TimeInterval = 5, _ cond: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if cond() { return true }; try? await Task.sleep(for: .milliseconds(25)) }
        return cond()
    }

    private func fullStack(_ sb: Sandbox, installed: Bool = true) async -> (AppModel, Project) {
        sb.write("Full/frontend/package.json", Sandbox.vite)
        sb.write("Full/backend/manage.py")
        if installed { try! FileManager.default.createDirectory(at: sb.scanRoot.appendingPathComponent("Full/frontend/node_modules"), withIntermediateDirectories: true) }
        let model = sb.makeModel()
        await model.refresh()
        return (model, model.projects[0])
    }

    private func override(_ model: AppModel, _ project: Project, _ kind: ServiceKind, _ command: String) {
        let dir = project.targets.first { $0.kind == kind }!.directory
        model.overrides.set(Override(command: command), forPath: OverrideStore.key(directory: dir, kind: kind))
    }

    @Test func fullStackOffersFrontendBackendBoth() async {
        let (model, project) = await fullStack(Sandbox())
        #expect(model.availableActions(for: project) == [.frontend, .backend, .both])
    }

    @Test func frontendOnlyOffersOnlyFrontend() async {
        let sb = Sandbox()
        sb.write("Site/package.json", Sandbox.vite)
        let model = sb.makeModel(); await model.refresh()
        #expect(model.availableActions(for: model.projects[0]) == [.frontend])
    }

    @Test func flutterOfferedOnlyWhenPubspecPresent() async {
        let sb = Sandbox()
        sb.write("Mob/pubspec.yaml", "dependencies:\n  flutter:\n    sdk: flutter\n")
        sb.write("Web/package.json", Sandbox.vite)
        let model = sb.makeModel(); await model.refresh()
        let mob = model.projects.first { $0.name == "Mob" }!
        let web = model.projects.first { $0.name == "Web" }!
        #expect(model.availableActions(for: mob) == [.flutter])
        #expect(!model.availableActions(for: web).contains(.flutter))
    }

    @Test func bothStartsTwoServicesAndStopStopsThem() async {
        let sb = Sandbox()
        let (model, project) = await fullStack(sb)
        override(model, project, .frontend, "sleep 30")
        override(model, project, .backend, "sleep 30")
        await model.refresh()
        let p = model.projects[0]
        await model.run(p, kinds: [.frontend, .backend])
        #expect(await waitUntil { model.processes.runningCount == 2 })
        #expect(model.isRunning(p))
        await model.stop(p)
        #expect(model.processes.runningCount == 0)
    }

    @Test func runWithMissingNodeModulesRequestsInstall() async {
        let sb = Sandbox()
        let (model, project) = await fullStack(sb, installed: false)
        await model.run(project, kinds: [.frontend])
        #expect(model.pendingInstall?.project.id == project.id)
        #expect(model.processes.runningCount == 0)
    }

    @Test func confirmingInstallRunsInstallThenStartsService() async {
        let sb = Sandbox()
        sb.write("Site/package.json", #"{"scripts":{"dev":"sleep 30"},"devDependencies":{"vite":"5"}}"#)
        let model = sb.makeModel(); await model.refresh()
        let p = model.projects[0]
        model.installCommandOverride = "mkdir -p node_modules"     // stands in for `npm install`
        await model.run(p, kinds: [.frontend])
        #expect(model.pendingInstall != nil)
        await model.confirmInstall()
        #expect(FileManager.default.fileExists(atPath: sb.scanRoot.appendingPathComponent("Site/node_modules").path))
        #expect(await waitUntil { model.processes.runningCount == 1 })
        await model.stop(p)
    }

    @Test func stoppingDuringInstallDoesNotStartTheService() async {
        let sb = Sandbox()
        sb.write("Site/package.json", #"{"scripts":{"dev":"sleep 30"},"devDependencies":{"vite":"5"}}"#)
        let model = sb.makeModel(); await model.refresh()
        let p = model.projects[0]
        model.installCommandOverride = "sleep 30"
        await model.run(p, kinds: [.frontend])
        let install = Task { await model.confirmInstall() }
        #expect(await waitUntil { model.processes.runningCount == 1 })
        await model.stop(p)
        await install.value
        try? await Task.sleep(for: .milliseconds(300))
        #expect(model.processes.runningCount == 0)
    }

    @Test func twoFrontendsInOneProjectBothStart() async {
        let sb = Sandbox()
        for d in ["web", "admin"] {
            sb.write("Mono/\(d)/package.json", Sandbox.vite)
            try! FileManager.default.createDirectory(at: sb.scanRoot.appendingPathComponent("Mono/\(d)/node_modules"), withIntermediateDirectories: true)
        }
        let model = sb.makeModel(); await model.refresh()
        let p = model.projects[0]
        for t in p.targets { model.overrides.set(Override(command: "sleep 30"), forPath: OverrideStore.key(directory: t.directory, kind: t.kind)) }
        await model.refresh()
        await model.run(model.projects[0], kinds: [.frontend])
        #expect(await waitUntil { model.processes.runningCount == 2 })
        await model.stop(model.projects[0])
    }

    @Test func cancellingInstallStartsNothing() async {
        let (model, project) = await fullStack(Sandbox(), installed: false)
        await model.run(project, kinds: [.frontend])
        model.cancelInstall()
        #expect(model.pendingInstall == nil)
        #expect(model.processes.runningCount == 0)
    }

    @Test func parsesFlutterDevicesJSON() {
        let json = #"[{"name":"macOS","id":"macos","targetPlatform":"darwin"},{"name":"iPhone 17","id":"ABC-123","targetPlatform":"ios"}]"#
        let devices = AppModel.parseFlutterDevices(json)
        #expect(devices.map(\.id) == ["macos", "ABC-123"])
        #expect(devices.map(\.name) == ["macOS", "iPhone 17"])
        #expect(AppModel.parseFlutterDevices("not json").isEmpty)
    }
}
