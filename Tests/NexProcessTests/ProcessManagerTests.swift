import Testing
import Foundation
import NexCore
@testable import NexProcess

@MainActor
private func waitUntil(_ timeout: TimeInterval = 15, _ condition: () -> Bool) async -> Bool {
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

/// Running and not a zombie. In a container whose first process doesn't reap orphans, a killed grandchild stays
/// a zombie forever, and `kill(pid, 0)` still succeeds for it.
private func isAlive(_ pid: Int32) -> Bool {
    guard kill(pid, 0) == 0 else { return false }
    #if os(Linux)
    if let stat = try? String(contentsOfFile: "/proc/\(pid)/stat", encoding: .utf8),
       let close = stat.lastIndex(of: ")"),
       stat[stat.index(after: close)...].trimmingCharacters(in: .whitespaces).hasPrefix("Z") { return false }
    #endif
    return true
}

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
    let id = ServiceID(projectID: "p", kind: .frontend, directory: FileManager.default.temporaryDirectory.path)

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
        let missing = target("echo hi", dir: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)"))
        pm.start(missing, projectID: "p")
        let mid = ProcessManager.id(for: missing, projectID: "p")
        if case .failed = pm.states[mid] {} else { Issue.record("expected failed, got \(String(describing: pm.states[mid]))") }
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
        let spaced = ProcessManager.id(for: target("pwd", dir: dir), projectID: "p")
        pm.start(target("pwd", dir: dir), projectID: "p")
        #expect(await waitUntil { pm.logs[spaced]?.contains { $0.contains("My Project") } == true })
    }

    @Test func stopKillsGrandchildThatIgnoresSigterm() async {
        let pm = ProcessManager(killTimeout: 0.4)
        pm.start(target("(trap '' TERM; sleep 300) & echo CHILD=$!; wait"), projectID: "p")
        #expect(await waitUntil { pm.logs[id]?.contains { $0.hasPrefix("CHILD=") } == true })
        let pid = Int32(pm.logs[id]!.first { $0.hasPrefix("CHILD=") }!.dropFirst(6))!
        await pm.stop(id)
        #expect(await waitUntil { !isAlive(pid) })
    }

    @Test func stoppingDockerRunsComposeStop() async throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("docker-stop-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: marker) }
        let pm = ProcessManager(killTimeout: 0.4)
        pm.dockerStopCommand = { _ in "touch '\(marker.path)'" }
        let dockerID = ServiceID(projectID: "p", kind: .docker, directory: FileManager.default.temporaryDirectory.path)
        pm.start(target("sleep 300", kind: .docker), projectID: "p")
        #expect(await waitUntil { pm.states[dockerID]?.isActive == true })
        await pm.stop(dockerID)
        #expect(FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func childDoesNotInheritOtherDescriptors() async throws {
        let pipe = Pipe()                         // not close-on-exec, like git's pipes
        let pm = ProcessManager()
        pm.start(target("sleep 300"), projectID: "p")
        try pipe.fileHandleForWriting.close()
        let reader = pipe.fileHandleForReading
        let sawEOF = LockedFlag()
        Thread.detachNewThread { _ = reader.readDataToEndOfFile(); sawEOF.set() }
        #expect(await waitUntil(2) { sawEOF.value })
        await pm.stopAll()
    }

    @Test func firstPortWinsOverLaterMentions() async {
        let pm = ProcessManager()
        pm.start(target("echo 'Local: http://localhost:4000/'; sleep 0.2; echo 'connected to localhost:5432'; sleep 30"), projectID: "p")
        #expect(await waitUntil { pm.logs[id]?.contains { $0.contains("5432") } == true })
        #expect(pm.states[id] == .running(port: 4000))
        await pm.stopAll()
    }

    @Test func configuredPortOverridesParsedPort() async {
        var t = target("echo 'http://localhost:5432/'; sleep 30")
        t.port = 9000
        let pm = ProcessManager()
        pm.start(t, projectID: "p")
        #expect(await waitUntil { pm.logs[id]?.isEmpty == false })
        #expect(pm.states[id] == .running(port: 9000))
        await pm.stopAll()
    }

    @Test func twoTargetsOfTheSameKindRunSideBySide() async throws {
        let a = FileManager.default.temporaryDirectory.appendingPathComponent("web-\(UUID().uuidString)")
        let b = FileManager.default.temporaryDirectory.appendingPathComponent("admin-\(UUID().uuidString)")
        for d in [a, b] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        let pm = ProcessManager()
        pm.start(target("sleep 300", dir: a), projectID: "p")
        pm.start(target("sleep 300", dir: b), projectID: "p")
        #expect(await waitUntil { pm.runningCount == 2 })
        await pm.stopAll()
    }

    @Test func userStoppedIsRecorded() async {
        let pm = ProcessManager()
        pm.start(target("sleep 300"), projectID: "p")
        #expect(await waitUntil { pm.states[id]?.isActive == true })
        await pm.stop(id)
        #expect(pm.wasUserStopped(id))
    }
}

final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock(); private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
