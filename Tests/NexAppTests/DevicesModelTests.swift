import Testing
import Foundation
import NexCore
@testable import NexApp
import NexTestSupport

final class FakeDeviceShell: DeviceShell, @unchecked Sendable {
    var outputs: [String: String] = [:]
    private(set) var ran: [[String]] = []
    private(set) var detached: [[String]] = []
    func output(_ args: [String]) async -> String? { ran.append(args); return outputs[args.joined(separator: " ")] }
    func launchDetached(_ args: [String]) { detached.append(args) }
}

private let simctlFixture = """
{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-0":[
  {"udid":"A1","isAvailable":true,"state":"Shutdown","name":"iPhone 17 Pro"},
  {"udid":"A2","isAvailable":true,"state":"Booted","name":"iPad Air"}]}}
"""

@MainActor
@Suite struct DevicesModelTests {
    private func model(_ shell: FakeDeviceShell) -> DevicesModel {
        DevicesModel(shell: shell, androidSDK: URL(fileURLWithPath: "/sdk"), hostOS: .macOS, shellPath: "/bin/zsh")
    }

    @Test func refreshLoadsSimulatorsEmulatorsAndConnectedDevices() async {
        let shell = FakeDeviceShell()
        shell.outputs["/usr/bin/xcrun simctl list devices available -j"] = simctlFixture
        shell.outputs["/sdk/emulator/emulator -list-avds"] = "Pixel_9\n"
        shell.outputs["/bin/zsh -lc flutter devices --machine"] = #"[{"name":"macOS","id":"macos","targetPlatform":"darwin","emulator":false}]"#
        let m = model(shell)
        await m.refresh()
        #expect(m.simulators.count == 2)
        #expect(m.avds == ["Pixel_9"])
        #expect(m.connected.map(\.id) == ["macos"])
        #expect(!m.isLoading)
    }

    @Test func bootingASimulatorBootsItAndOpensTheSimulatorApp() async {
        let shell = FakeDeviceShell()
        let m = model(shell)
        await m.boot(SimulatorDevice(udid: "A1", name: "iPhone 17 Pro", runtime: "iOS 26.0", isBooted: false))
        #expect(shell.ran.contains(["/usr/bin/xcrun", "simctl", "boot", "A1"]))
        #expect(shell.ran.contains(["/usr/bin/open", "-a", "Simulator"]))
    }

    @Test func shuttingDownASimulator() async {
        let shell = FakeDeviceShell()
        await model(shell).shutdown(SimulatorDevice(udid: "A2", name: "iPad", runtime: "iOS 26.0", isBooted: true))
        #expect(shell.ran.contains(["/usr/bin/xcrun", "simctl", "shutdown", "A2"]))
    }

    @Test func launchingAnAndroidEmulatorRunsItDetached() {
        let shell = FakeDeviceShell()
        model(shell).launch(avd: "Pixel_9")
        #expect(shell.detached == [["/sdk/emulator/emulator", "-avd", "Pixel_9"]])
    }

    @Test func withoutAnAndroidSDKThereAreNoEmulatorsAndAHint() async {
        let shell = FakeDeviceShell()
        let m = DevicesModel(shell: shell, androidSDK: nil, hostOS: .macOS, shellPath: "/bin/zsh")
        await m.refresh()
        #expect(m.avds.isEmpty)
        #expect(m.androidHint != nil)
        m.launch(avd: "Pixel_9")
        #expect(shell.detached.isEmpty)
    }
}
