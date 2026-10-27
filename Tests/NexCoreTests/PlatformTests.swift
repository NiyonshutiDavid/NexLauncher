import Testing
import Foundation
@testable import NexCore

@Suite struct PlatformTests {
    let home = URL(fileURLWithPath: "/home/alex")

    private func paths(_ os: HostOS, env: [String: String] = [:], existing: Set<String> = []) -> PlatformPaths {
        Platform.paths(os: os, home: home, environment: env, exists: { existing.contains($0.path) })
    }

    @Test func macPathsUnchanged() {
        let p = paths(.macOS, existing: [])
        #expect(p.configDirectory.path == "/home/alex/Library/Application Support/NexLauncher")
        #expect(p.dataDirectory == p.configDirectory)
        #expect(p.defaultScanRoot.path == "/home/alex/Documents/Nexventures")
    }

    @Test func linuxUsesXDG() {
        let set = paths(.linux, env: ["XDG_CONFIG_HOME": "/x/cfg", "XDG_DATA_HOME": "/x/data"])
        #expect(set.configDirectory.path == "/x/cfg/nexlauncher")
        #expect(set.dataDirectory.path == "/x/data/nexlauncher")
        let unset = paths(.linux)
        #expect(unset.configDirectory.path == "/home/alex/.config/nexlauncher")
        #expect(unset.dataDirectory.path == "/home/alex/.local/share/nexlauncher")
    }

    @Test func defaultScanRootFallsBack() {
        #expect(paths(.linux, existing: ["/home/alex/Projects", "/home/alex/Documents"]).defaultScanRoot.path == "/home/alex/Projects")
        #expect(paths(.linux, existing: ["/home/alex/Documents"]).defaultScanRoot.path == "/home/alex/Documents")
        #expect(paths(.linux).defaultScanRoot.path == "/home/alex")
    }

    @Test func androidSDKCandidates() {
        let linux = paths(.linux, env: ["ANDROID_HOME": "/opt/android"]).androidSDKCandidates.map(\.path)
        #expect(linux == ["/opt/android", "/home/alex/Android/Sdk"])
        let mac = paths(.macOS).androidSDKCandidates.map(\.path)
        #expect(mac == ["/home/alex/Library/Android/sdk"])
    }

    @Test func loginShellOrder() {
        #expect(Platform.loginShell(environment: ["SHELL": "/usr/bin/fish"], passwdShell: "/bin/bash") == "/usr/bin/fish")
        #expect(Platform.loginShell(environment: [:], passwdShell: "/bin/bash") == "/bin/bash")
        #expect(Platform.loginShell(environment: ["SHELL": ""], passwdShell: nil) == "/bin/sh")
    }

    @Test func iOSSimulatorsOnlyOnMac() {
        #expect(Platform.supportsIOSSimulators(on: .macOS))
        #expect(!Platform.supportsIOSSimulators(on: .linux))
    }
}

@Suite struct SettingsPortabilityTests {
    @Test func roundTripKeepsMacKeys() throws {
        let json = #"""
        {"displayName":"Alex","scanRoot":"file:///home/alex/Projects/","showDockIcon":true,"pinnedProjectIDs":[],
         "widgetsConfirmed":true,"avatarPhotoPath":"/home/alex/me.png","futureKey":{"nested":[1,"two",null,true]}}
        """#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        let again = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
        #expect(again["widgetsConfirmed"] as? Bool == true)
        #expect(again["avatarPhotoPath"] as? String == "/home/alex/me.png")
        let future = again["futureKey"] as? [String: Any]
        let nested = future?["nested"] as? [Any]
        #expect(nested?.count == 4)
        #expect(nested?[1] as? String == "two")
    }
}
