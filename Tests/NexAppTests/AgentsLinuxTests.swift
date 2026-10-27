import Testing
import Foundation
import NexCore
@testable import NexApp
import NexTestSupport

@MainActor
@Suite struct AgentsLinuxTests {
    /// Linux has no Antigravity app bundle: without the agy CLI the model explains instead of opening anything.
    @Test func antigravityWithoutCLIDoesNotOpenApp() async {
        let sb = Sandbox()
        sb.write("Site/package.json", Sandbox.vite)
        let services = RecordingPlatformServices()
        let m = sb.makeModel(services: services, hostOS: .linux)
        m.reloadWidgets = {}
        await m.refresh()
        #expect(m.startAgent(.antigravity, task: "Add a footer", project: m.projects[0]) == nil)
        #expect(services.openedWithApp.isEmpty)
        #expect(m.agentError == "Install Antigravity's command-line tool (agy) to run tasks here.")
    }

    /// Inside the Flatpak, agent detection and device tools must run on the host, where they are installed.
    @Test func deviceAndAgentCommandsRunOnTheHostInsideFlatpak() {
        let detect = AgentCatalog.detectCommand("claude")
        let inside = SystemDeviceShell(flatpak: true).invocation(detect)
        #expect(inside.executable == HostCommand.flatpakSpawn)
        #expect(inside.arguments == ["--host"] + detect)
        let outside = SystemDeviceShell(flatpak: false).invocation(["/sdk/emulator/emulator", "-list-avds"])
        #expect(outside.executable == "/sdk/emulator/emulator")
        #expect(outside.arguments == ["-list-avds"])
    }
}
