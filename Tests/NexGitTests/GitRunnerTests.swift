import Testing
import Foundation
@testable import NexGit

@Suite struct GitRunnerTests {
    @Test func timeoutFiresEvenWhenGitExitedButAChildHoldsThePipe() async {
        let dir = FileManager.default.temporaryDirectory
        let start = Date()
        await #expect(throws: GitError.timeout) {
            // git exits at once, but the backgrounded sleep keeps stdout open for 20 s.
            _ = try await GitRunner().runRaw(["-c", "alias.bg=!sleep 20 &", "bg"], in: dir, timeout: 0.4)
        }
        #expect(Date().timeIntervalSince(start) < 10)
    }
}
