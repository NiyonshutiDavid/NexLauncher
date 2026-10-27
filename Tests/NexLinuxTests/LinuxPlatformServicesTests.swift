import Testing
import Foundation
@testable import NexLinux

@MainActor
final class RecordingLauncher: URILaunching {
    var launched: [String] = []
    func launch(uri: String) { launched.append(uri) }
}

@MainActor
@Suite struct LinuxPlatformServicesTests {
    @Test func openURLUsesTheDefaultHandler() {
        let launcher = RecordingLauncher()
        let services = LinuxPlatformServices(launcher: launcher)
        services.open(URL(string: "http://localhost:5173/")!)
        #expect(launcher.launched == ["http://localhost:5173/"])
    }

    @Test func revealOpensTheContainingFolder() {
        let launcher = RecordingLauncher()
        let services = LinuxPlatformServices(launcher: launcher)
        services.reveal(URL(fileURLWithPath: "/home/alex/Projects/Café App/package.json"))
        #expect(launcher.launched == ["file:///home/alex/Projects/Caf%C3%A9%20App/"])
    }
}
