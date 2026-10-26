import Foundation

/// A node in the project tree: a runnable app, or a collection of apps (e.g. `intern-sessions/week1`, `week2`).
public struct ProjectNode: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable { case app, collection }

    public let id: String
    public let name: String
    public let url: URL
    public let kind: Kind
    public let project: Project?
    public var children: [ProjectNode]

    public init(id: String, name: String, url: URL, kind: Kind, project: Project?, children: [ProjectNode]) {
        self.id = id
        self.name = name
        self.url = url
        self.kind = kind
        self.project = project
        self.children = children
    }

    /// This node's project (if any) followed by every descendant's.
    public var apps: [Project] {
        (project.map { [$0] } ?? []) + children.flatMap(\.apps)
    }
}
