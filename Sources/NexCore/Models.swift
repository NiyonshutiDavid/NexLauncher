import Foundation

public enum ServiceKind: String, Codable, Sendable, CaseIterable {
    case frontend, backend, flutter, docker
}

public struct ServiceTarget: Codable, Hashable, Sendable {
    public let kind: ServiceKind
    public let directory: URL
    public let framework: String?
    public var command: String

    public init(kind: ServiceKind, directory: URL, framework: String?, command: String) {
        self.kind = kind
        self.directory = directory
        self.framework = framework
        self.command = command
    }
}

public struct Project: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let root: URL
    public var targets: [ServiceTarget]

    public init(id: String, name: String, root: URL, targets: [ServiceTarget]) {
        self.id = id
        self.name = name
        self.root = root
        self.targets = targets
    }

    public var isFullStack: Bool {
        targets.contains { $0.kind == .frontend } && targets.contains { $0.kind == .backend }
    }
}

public struct Greeter {
    public static func greeting(for date: Date, name: String, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let part: String
        switch hour {
        case 5...11: part = "morning"
        case 12...17: part = "afternoon"
        case 18...21: part = "evening"
        default: part = "night"
        }
        return "Good \(part), \(name)"
    }
}
