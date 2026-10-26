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

    public var running: [Running]
    public var pinned: [PinnedProject]

    public init(running: [Running], pinned: [PinnedProject]) {
        self.running = running
        self.pinned = pinned
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
