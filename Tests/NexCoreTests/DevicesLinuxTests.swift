import Testing
import Foundation
@testable import NexCore

@Suite struct DevicesLinuxTests {
    @Test func sdkFromAndroidHome() {
        let home = URL(fileURLWithPath: "/opt/android")
        let found = DeviceParsers.androidSDK(candidates: [home, URL(fileURLWithPath: "/home/alex/Android/Sdk")],
                                             exists: { $0.path == "/opt/android/emulator/emulator" })
        #expect(found == home)
    }

    @Test func sdkDefaultLinuxPath() {
        let candidates = Platform.paths(os: .linux, home: URL(fileURLWithPath: "/home/alex"), environment: [:], exists: { _ in false }).androidSDKCandidates
        let found = DeviceParsers.androidSDK(candidates: candidates, exists: { $0.path == "/home/alex/Android/Sdk/emulator/emulator" })
        #expect(found?.path == "/home/alex/Android/Sdk")
    }
}
