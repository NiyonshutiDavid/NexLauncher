import Testing
import Foundation
@testable import NexCore

@Suite struct PipeSafetyTests {
    /// A long-lived child started while our pipe is open must not keep it open: once we close our write end,
    /// reading must reach end-of-file straight away (otherwise a git call waits for an unrelated emulator).
    @Test func unrelatedChildDoesNotKeepPipeOpen() throws {
        let pipe = Pipe.closeOnExec()
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["3"]
        try sleeper.run()
        defer { sleeper.terminate() }
        try pipe.fileHandleForWriting.close()
        let start = Date()
        _ = pipe.fileHandleForReading.readDataToEndOfFile()
        #expect(Date().timeIntervalSince(start) < 1)
    }
}
