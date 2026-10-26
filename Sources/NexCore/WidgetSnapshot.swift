import Foundation

/// What the widgets display. The app writes it; the widget extension reads it.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public struct Running: Codable, Equatable, Sendable {
        public let projectName: String
        public let kind: ServiceKind
        public let port: Int?
        public init(projectName: String, kind: ServiceKind, port: Int?) {
            self.projectName = projectName
            self.kind = kind
            self.port = port
        }
    }
    public struct PinnedProject: Codable, Equatable, Sendable {
        public let id: String
        public let name: String
        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    public struct TaskSummary: Codable, Equatable, Sendable {
        public let title: String
        public let projectName: String
        public let done: Bool
        public init(title: String, projectName: String, done: Bool) {
            self.title = title
            self.projectName = projectName
            self.done = done
        }
    }

    public var running: [Running]
    public var pinned: [PinnedProject]
    /// Recently completed tasks first, then open ones.
    public var tasks: [TaskSummary] = []
    public var openTaskCount: Int = 0

    public init(running: [Running], pinned: [PinnedProject], tasks: [TaskSummary] = [], openTaskCount: Int = 0) {
        self.running = running
        self.pinned = pinned
        self.tasks = tasks
        self.openTaskCount = openTaskCount
    }

    enum CodingKeys: String, CodingKey { case running, pinned, tasks, openTaskCount }

    /// Tolerant: a snapshot written by an older build (no tasks) still decodes.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        running = (try? c.decode([Running].self, forKey: .running)) ?? []
        pinned = (try? c.decode([PinnedProject].self, forKey: .pinned)) ?? []
        tasks = (try? c.decode([TaskSummary].self, forKey: .tasks)) ?? []
        openTaskCount = (try? c.decode(Int.self, forKey: .openTaskCount)) ?? 0
    }
}

public enum SharedContainer {
    static let fileName = "widget-snapshot.json"

    /// The app writes here and the sandboxed widget reads it through a read-only home-relative exception.
    /// (An App Group would need a provisioning profile; this keeps the personal build simple.)
    public static var defaultDirectory: URL { AppSettings.supportDirectory }

    public static func write(_ snapshot: WidgetSnapshot, to directory: URL = defaultDirectory) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
        }
    }

    public static func read(from directory: URL = defaultDirectory) -> WidgetSnapshot {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)),
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return WidgetSnapshot(running: [], pinned: [])
        }
        return snap
    }
}
