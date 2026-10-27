import Testing
import Foundation
import NexCore
@testable import NexApp

@MainActor
@Suite struct DevicesLinuxModelTests {
    @Test func noIOSSectionOnLinux() async {
        let shell = FakeDeviceShell()
        let m = DevicesModel(shell: shell, androidSDK: nil, hostOS: .linux)
        await m.refresh()
        #expect(!shell.ran.contains { $0.contains { $0.contains("xcrun") } })
        #expect(m.simulators.isEmpty)
        #expect(!m.showsIOSSimulators)
    }

    @Test func flutterDevicesUseThePlatformShell() async {
        let shell = FakeDeviceShell()
        await DevicesModel(shell: shell, androidSDK: nil, hostOS: .linux, shellPath: "/bin/bash").refresh()
        #expect(shell.ran.contains(["/bin/bash", "-lc", "flutter devices --machine"]))
        let mac = FakeDeviceShell()
        await DevicesModel(shell: mac, androidSDK: nil, hostOS: .macOS).refresh()
        #expect(mac.ran.contains(["/bin/zsh", "-lc", "flutter devices --machine"]))
    }
}
