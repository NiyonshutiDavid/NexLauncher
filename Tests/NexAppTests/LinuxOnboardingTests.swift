import Testing
import Foundation
import NexCore
@testable import NexApp
import NexTestSupport

@MainActor
@Suite struct LinuxOnboardingTests {
    @Test func missingFolderOffersChoice() throws {
        let sb = Sandbox()
        let model = sb.makeModel(hostOS: .linux)
        let flow = OnboardingModel(model: model)
        flow.folder = sb.root.appendingPathComponent("Projects")
        flow.step = .projects
        #expect(!flow.folderExists)
        #expect(!flow.canAdvance)
        try flow.createFolder()
        #expect(flow.folderExists)
        #expect(flow.canAdvance)
    }
}
