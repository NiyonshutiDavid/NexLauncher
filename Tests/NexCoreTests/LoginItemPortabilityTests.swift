import Testing
import Foundation
@testable import NexCore

@MainActor
@Suite struct LoginItemPortabilityTests {
    @Test func unsupportedLoginItemRefusesAndStaysOff() {
        let launch = LaunchAtLogin(controller: UnsupportedLoginItem())
        launch.set(true)
        #expect(!launch.isEnabled)
        #expect(launch.errorMessage == "Launch at login isn't available on this system yet.")
        launch.set(false)
        #expect(launch.errorMessage == nil)
    }
}
