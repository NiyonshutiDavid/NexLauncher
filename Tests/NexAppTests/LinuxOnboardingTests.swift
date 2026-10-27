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

    /// A typed `~/…` path means the home folder, not a folder named "~" in the working directory.
    @Test func typedTildeMeansHome() {
        let sb = Sandbox()
        let flow = OnboardingModel(model: sb.makeModel(hostOS: .linux))
        flow.setFolder(path: "~/Projects")
        #expect(flow.folder.path == AppSettings.realHome.appendingPathComponent("Projects").path)
        flow.setFolder(path: "/srv/code")
        #expect(flow.folder.path == "/srv/code")
    }
}
