import Testing
import Foundation
@testable import NexTerminal

@MainActor
private func waitUntil(_ timeout: TimeInterval = 20, _ cond: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end { if cond() { return true }; try? await Task.sleep(for: .milliseconds(50)) }
    return cond()
}

private func makeDir(_ name: String) -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("nexterm-\(UUID().uuidString)").appendingPathComponent(name)
    try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

@MainActor
@Suite(.serialized) struct TerminalSessionTests {
    @Test func startsInRequestedDirectoryWithSpacesAndQuotes() async {
        let dir = makeDir(#"My "Proj" x"#)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let s = TerminalSession(directory: dir)
        s.start()
        #expect(await waitUntil { s.isAlive })
        s.send(#"echo "cwd=[$(basename "$PWD")]""# + "\n")
        #expect(await waitUntil { s.outputForTesting.contains(#"cwd=[My "Proj" x]"#) })
        s.terminate()
    }

    @Test func echoesInput() async {
        let dir = makeDir("echo")
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let s = TerminalSession(directory: dir)
        s.start()
        s.send("echo nex-$((20+22))\n")
        #expect(await waitUntil { s.outputForTesting.contains("nex-42") })
        s.terminate()
    }

    @Test func terminateEndsTheShell() async {
        let s = TerminalSession(directory: makeDir("t1"))
        s.start()
        #expect(await waitUntil { s.isAlive })
        let pid = s.shellPID
        #expect(pid > 0)
        s.terminate()
        #expect(await waitUntil { !s.isAlive })
        #expect(await waitUntil { kill(pid, 0) != 0 })
    }

    @Test func closingTabTerminatesItsSession() async {
        let tabs = TerminalTabs()
        let s = tabs.open(at: makeDir("tab"))
        #expect(await waitUntil { s.isAlive })
        let pid = s.shellPID
        tabs.close(s.id)
        #expect(tabs.sessions.isEmpty)
        #expect(await waitUntil { kill(pid, 0) != 0 })
    }

    @Test func foregroundProgramDetected() async {
        let s = TerminalSession(directory: makeDir("fg"))
        s.start()
        #expect(await waitUntil { s.isAlive })
        #expect(await waitUntil { !s.hasForegroundProgram })     // idle prompt
        s.send("sleep 30\n")
        #expect(await waitUntil { s.hasForegroundProgram })
        s.terminate()
        #expect(await waitUntil { !s.hasForegroundProgram })
    }

    @Test func tabsKnowAboutForegroundPrograms() async {
        let tabs = TerminalTabs()
        let s = tabs.open(at: makeDir("any"))
        #expect(await waitUntil { s.isAlive })
        #expect(await waitUntil { !tabs.anyForegroundProgram })
        s.send("sleep 30\n")
        #expect(await waitUntil { tabs.anyForegroundProgram })
        tabs.closeAll()
        #expect(tabs.sessions.isEmpty)
    }

    @Test func multipleTabsAreIndependent() async {
        let tabs = TerminalTabs()
        let a = tabs.open(at: makeDir("alpha")), b = tabs.open(at: makeDir("beta"))
        #expect(a.id != b.id && tabs.sessions.count == 2 && tabs.selectedID == b.id)
        a.send("echo only-in-alpha\n")
        #expect(await waitUntil { a.outputForTesting.contains("only-in-alpha") })
        try? await Task.sleep(for: .milliseconds(300))
        #expect(!b.outputForTesting.contains("only-in-alpha"))
        tabs.closeAll()
    }
}
