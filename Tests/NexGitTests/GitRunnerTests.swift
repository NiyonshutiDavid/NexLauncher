import Testing
import Foundation
@testable import NexGit

@Suite struct GitRunnerTests {
    @Test func timeoutStopsGitThatRunsTooLong() async {
        let dir = FileManager.default.temporaryDirectory
        let start = Date()
        await #expect(throws: GitError.timeout) {
            // git waits for its 20 s alias, and that sleep keeps the pipes open after git is stopped.
            _ = try await GitRunner().runRaw(["-c", "alias.slow=!sleep 20", "slow"], in: dir, timeout: 0.4)
        }
        #expect(Date().timeIntervalSince(start) < 10)
    }
}
