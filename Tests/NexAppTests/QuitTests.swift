import Testing
import Foundation
import NexCore
@testable import NexApp
import NexTestSupport

/// Quitting must never leave services, agents or terminal programs running unsupervised (both apps use this).
@MainActor
@Suite struct QuitTests {
    @Test func summaryNamesWhatIsStillRunning() {
        let terminals = RecordingTerminalHost()
        let m = Sandbox().makeModel(terminals: terminals)
        #expect(m.quitSummary == nil)
        terminals.hasRunningPrograms = true
        #expect(m.quitSummary == "A program is still running in a terminal")
    }

    @Test func stopEverythingClosesTerminals() async {
        let terminals = RecordingTerminalHost()
        let m = Sandbox().makeModel(terminals: terminals)
        terminals.openTab(at: URL(fileURLWithPath: "/tmp"), command: nil)
        await m.stopEverything()
        #expect(terminals.tabs.isEmpty)
    }
}
