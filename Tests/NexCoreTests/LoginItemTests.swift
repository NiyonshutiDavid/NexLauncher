import Testing
import Foundation
@testable import NexCore

private final class FakeLoginItem: LoginItemControlling, @unchecked Sendable {
    var isEnabled = false
    var failure: Error?
    func setEnabled(_ on: Bool) throws {
        if let failure { throw failure }
        isEnabled = on
    }
}

private struct Boom: LocalizedError { var errorDescription: String? { "Not permitted" } }

@MainActor
@Suite struct LoginItemTests {
    @Test func toggleCallsSetEnabled() {
        let fake = FakeLoginItem()
        let model = LaunchAtLogin(controller: fake)
        #expect(!model.isEnabled)
        model.set(true)
        #expect(fake.isEnabled && model.isEnabled)
        #expect(model.errorMessage == nil)
        model.set(false)
        #expect(!fake.isEnabled && !model.isEnabled)
    }

    @Test func failureSurfacedNotSwallowedAndStateStaysTruthful() {
        let fake = FakeLoginItem()
        fake.failure = Boom()
        let model = LaunchAtLogin(controller: fake)
        model.set(true)
        #expect(model.errorMessage == "Not permitted")
        #expect(!model.isEnabled)
    }

    @Test func refreshReadsCurrentSystemState() {
        let fake = FakeLoginItem()
        let model = LaunchAtLogin(controller: fake)
        fake.isEnabled = true
        model.refresh()
        #expect(model.isEnabled)
    }
}
