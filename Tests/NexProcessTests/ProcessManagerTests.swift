import Testing
import Foundation
import NexCore
@testable import NexProcess

@MainActor
private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(25))
    }
    return condition()
}

private func target(_ command: String, kind: ServiceKind = .frontend, dir: URL = FileManager.default.temporaryDirectory) -> ServiceTarget {
    ServiceTarget(kind: kind, directory: dir, framework: nil, command: command)
}

private func isAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 }

@Suite struct PortParserTests {
    @Test func parsesVitePortWithAnsi() {
        #expect(PortParser.port(in: "\u{1B}[32m  ➜  Local:   http://localhost:5173/\u{1B}[0m") == 5173)
    }
    @Test func parsesDjangoPort() {
        #expect(PortParser.port(in: "Starting development server at http://127.0.0.1:8000/") == 8000)
    }
    @Test func parsesPortWord() {
        #expect(PortParser.port(in: "Server listening on port 3001") == 3001)
    }
    @Test func noPortReturnsNil() {
        #expect(PortParser.port(in: "compiled successfully in 120ms") == nil)
    }
}

@MainActor
@Suite(.serialized) struct ProcessManagerTests {
    let id = ServiceID(projectID: "p", kind: .frontend)

    @Test func startCapturesLogLinesAndPort() async {
        let pm = ProcessManager()
        pm.start(target("echo 'Local: http://localhost:4321/'; sleep 30"), projectID: "p")
        #expect(await waitUntil { pm.logs[id]?.contains { $0.contains("4321") } == true })
        #expect(await waitUntil { pm.states[id] == .running(port: 4321) })
        await pm.stopAll()
    }

    @Test func stopTerminatesGroupAndChildren() async {
        let pm = ProcessManager()
        pm.start(target("sleep 300 & echo CHILD=$!; wait"), projectID: "p")
        #expect(await waitUntil { pm.logs[id]?.contains { $0.hasPrefix("CHILD=") } == true })
        let pid = Int32(pm.logs[id]!.first { $0.hasPrefix("CHILD=") }!.dropFirst(6))!
        #expect(isAlive(pid))
        await pm.stop(id)
        #expect(await waitUntil { !isAlive(pid) })
        #expect(pm.states[id] == .stopped)
    }

    @Test func stopEscalatesToSigkill() async {
        let pm = ProcessManager(killTimeout: 0.4)
        pm.start(target("trap '' TERM; echo READY; while true; do sleep 1; done"), projectID: "p")
        #expect(await waitUntil { pm.logs[id]?.contains("READY") == true })
        await pm.stop(id)
        #expect(pm.states[id] == .stopped)
        #expect(pm.runningCount == 0)
    }

    @Test func immediateNonZeroExitBecomesFailedWithLastLine() async {
        let pm = ProcessManager()
        pm.start(target("echo boom; exit 3"), projectID: "p")
        #expect(await waitUntil { if case .failed = pm.states[id] { return true } else { return false } })
        guard case .failed(let message) = pm.states[id] else { return }
        #expect(message.contains("3"))
        #expect(message.contains("boom"))
    }

    @Test func cleanExitBecomesStopped() async {
        let pm = ProcessManager()
        pm.start(target("echo done"), projectID: "p")
        #expect(await waitUntil { pm.states[id] == .stopped })
    }

    @Test func missingDirectoryGivesFailedState() async {
        let pm = ProcessManager()
        pm.start(target("echo hi", dir: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")), projectID: "p")
        if case .failed = pm.states[id] {} else { Issue.record("expected failed, got \(String(describing: pm.states[id]))") }
    }

    @Test func stopAllLeavesNoRunning() async {
        let pm = ProcessManager()
        pm.start(target("sleep 300"), projectID: "a")
        pm.start(target("sleep 300", kind: .backend), projectID: "a")
        #expect(await waitUntil { pm.runningCount == 2 })
        await pm.stopAll()
        #expect(pm.runningCount == 0)
    }

    @Test func logsCapAt5000Lines() async {
        let pm = ProcessManager()
        pm.start(target("i=0; while [ $i -lt 6000 ]; do echo line$i; i=$((i+1)); done"), projectID: "p")
        #expect(await waitUntil(10) { pm.states[id] == .stopped })
        #expect(await waitUntil { pm.logs[id]?.last == "line5999" })
        #expect(pm.logs[id]!.count <= 5000)
    }

    @Test func pathWithSpacesWorks() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("My Project \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pm = ProcessManager()
        pm.start(target("pwd", dir: dir), projectID: "p")
        #expect(await waitUntil { pm.logs[id]?.contains { $0.contains("My Project") } == true })
    }
}
