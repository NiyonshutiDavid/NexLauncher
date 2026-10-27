import Foundation
import AppKit
import Observation
import NexCore
import NexProcess

/// One task handed to an agent: its live progress and outcome.
@MainActor @Observable
public final class AgentRun: Identifiable {
    public enum Status: Equatable, Sendable { case running, succeeded, failed(String), stopped }

    public let id = UUID()
    public let agent: AgentKind
    public let projectID: String
    public let projectName: String
    public let projectRoot: URL
    public let task: String
    public let autonomy: AgentAutonomy
    public let linkedTaskID: UUID?
    /// The run this one replies to (a follow-up in the same conversation).
    public let parentID: UUID?
    /// Claude Code's session id, used to resume the conversation.
    public internal(set) var sessionID: String?
    public let startedAt = Date()
    public internal(set) var status: Status = .running
    public internal(set) var events: [AgentEvent] = []
    public internal(set) var endedAt: Date?
    public internal(set) var summary: String?
    public internal(set) var costUSD: Double?
    var pid: pid_t = 0
    var stopRequested = false
    var reportedSuccess: Bool?

    init(agent: AgentKind, project: Project, task: String, autonomy: AgentAutonomy, linkedTaskID: UUID?, parentID: UUID? = nil, sessionID: String? = nil) {
        self.parentID = parentID
        self.sessionID = sessionID
        self.agent = agent
        projectID = project.id
        projectName = project.name
        projectRoot = project.root
        self.task = task
        self.autonomy = autonomy
        self.linkedTaskID = linkedTaskID
    }

    public var isRunning: Bool { status == .running }

    func append(_ lines: [String]) {
        for line in lines {
            if agent == .claude, let id = ClaudeStreamParser.sessionID(from: line) { sessionID = id }
            let parsed = agent == .claude ? ClaudeStreamParser.events(from: line)
                : (line.trimmingCharacters(in: .whitespaces).isEmpty ? [] : [AgentEvent.text(PortParser.stripANSI(line))])
            for event in parsed {
                if case .result(let ok, let text, let cost) = event { reportedSuccess = ok; summary = text; costUSD = cost }
                events.append(event)
            }
        }
        if events.count > 3000 { events.removeFirst(events.count - 3000) }
    }

    /// What the agent said last: its final result, or its latest message.
    public var answer: String? {
        if let summary, !summary.isEmpty { return summary }
        return lastText
    }

    var lastText: String? {
        events.reversed().lazy.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.first
    }
}

public struct AgentStatus: Equatable, Sendable {
    public var installed: Bool
    public var version: String?
}

/// Which agents are available on this Mac.
@MainActor @Observable
public final class AgentCatalog {
    public private(set) var statuses: [AgentKind: AgentStatus] = [:]
    public private(set) var isLoading = false
    private var commandLineKinds: Set<AgentKind> = []
    private let shell: DeviceShell
    private let antigravityApp: URL

    public init(shell: DeviceShell = SystemDeviceShell(), antigravityApp: URL = URL(fileURLWithPath: "/Applications/Antigravity.app")) {
        self.shell = shell
        self.antigravityApp = antigravityApp
    }

    public func status(_ kind: AgentKind) -> AgentStatus {
        if kind == .custom { return AgentStatus(installed: true, version: nil) }
        return statuses[kind] ?? AgentStatus(installed: false, version: nil)
    }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        var found: Set<AgentKind> = []
        for kind in AgentKind.allCases {
            guard let binary = kind.binary else { continue }
            let out = await shell.output(Self.detectCommand(binary))
            let version = out?.split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) }
            let installed = !(version ?? "").isEmpty
            if installed { found.insert(kind) }
            statuses[kind] = AgentStatus(installed: installed, version: installed ? version : nil)
        }
        commandLineKinds = found
        // Without agy, Antigravity still counts as available through its app.
        if !found.contains(.antigravity) {
            statuses[.antigravity] = AgentStatus(installed: FileManager.default.fileExists(atPath: antigravityApp.path), version: nil)
        }
    }

    /// Whether the agent's command-line tool was found (Antigravity may only have its app).
    public func hasCommandLine(_ kind: AgentKind) -> Bool { commandLineKinds.contains(kind) }

    /// Finds a CLI through the login shell, also looking in ~/.local/bin.
    public static func detectCommand(_ binary: String) -> [String] {
        ["/bin/zsh", "-lc", "export \(AgentKind.localBinPath); command -v \(binary) >/dev/null && \(binary) --version"]
    }
}

/// What the AI composer is pre-filled with (e.g. from a task's "Ask AI").
public struct AgentDraft: Equatable, Sendable {
    public var projectID: String
    public var text: String
    public var taskID: UUID?
}
