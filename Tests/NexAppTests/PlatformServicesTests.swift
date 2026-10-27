import Testing
import Foundation
import NexCore
@testable import NexApp
import NexTestSupport

@MainActor
@Suite(.serialized) struct PlatformServicesTests {
    @Test func copyTaskForAntigravity() async {
        let sb = Sandbox()
        sb.write("Site/package.json", Sandbox.vite)
        let services = RecordingPlatformServices()
        let m = sb.makeModel(services: services, hostOS: .macOS)
        m.reloadWidgets = {}
        await m.refresh()
        let project = m.projects[0]
        // No agy CLI detected: Antigravity opens the project in the app with the task on the clipboard.
        #expect(m.startAgent(.antigravity, task: "Add a footer", project: project) == nil)
        #expect(services.copied == ["Add a footer"])
        #expect(services.openedWithApp.first?.files == [project.root])
        #expect(services.openedWithApp.first?.app.path == "/Applications/Antigravity.app")
    }

    @Test func showMainWindowActivates() {
        let services = RecordingPlatformServices()
        let m = Sandbox().makeModel(services: services)
        var reopened = 0
        m.openMainWindowAction = { reopened += 1 }
        services.hasWindow = true
        m.showMainWindow()
        #expect(services.activations == 1 && reopened == 0)
        services.hasWindow = false
        m.showMainWindow()
        #expect(services.activations == 2 && reopened == 1)
    }

    @Test func dockIconPolicyGoesThroughServices() {
        let services = RecordingPlatformServices()
        let m = Sandbox().makeModel(services: services)
        m.settings.settings.showDockIcon = false
        m.applyDockIconPolicy()
        #expect(services.dockIconVisible == [false])
    }
}
