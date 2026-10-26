import Foundation
import NexCore

public enum KindFilter: String, CaseIterable, Identifiable, Sendable {
    case fullStack = "Full-stack", frontend = "Frontend", backend = "Backend", flutter = "Flutter", docker = "Docker", app = "App"
    public var id: String { rawValue }

    func matches(_ p: Project) -> Bool {
        switch self {
        case .fullStack: return p.isFullStack
        case .frontend: return p.targets.contains { $0.kind == .frontend }
        case .backend: return p.targets.contains { $0.kind == .backend }
        case .flutter: return p.targets.contains { $0.kind == .flutter }
        case .docker: return p.targets.contains { $0.kind == .docker }
        case .app: return p.targets.contains { $0.kind == .app }
        }
    }
}

public enum GitFilter: String, CaseIterable, Sendable { case any = "Any", changes = "Unsaved changes", clean = "Clean" }

/// How collections (folders of several apps) appear while browsing.
public enum CollectionMode: String, CaseIterable, Sendable {
    case show = "As cards", expand = "Show their apps", hide = "Hide", only = "Only collections"
}

public struct ProjectFilterSet: Equatable, Sendable {
    public var kinds: Set<KindFilter> = []
    public var frameworks: Set<String> = []
    public var git: GitFilter = .any
    public var onlyRunning = false
    public var onlyPinned = false
    public var collections: CollectionMode = .show

    public init() {}

    /// Filters that look at a project's own attributes (not the collections setting).
    var narrowsProjects: Bool { !kinds.isEmpty || !frameworks.isEmpty || git != .any || onlyRunning || onlyPinned }
    public var isActive: Bool { narrowsProjects || collections != .show }
    public var activeCount: Int {
        (kinds.isEmpty ? 0 : 1) + (frameworks.isEmpty ? 0 : 1) + (git == .any ? 0 : 1)
            + (onlyRunning ? 1 : 0) + (onlyPinned ? 1 : 0) + (collections == .show ? 0 : 1)
    }
}

extension AppModel {
    public var availableFrameworks: [String] {
        Set(projects.flatMap { $0.targets.compactMap(\.framework) }).sorted()
    }

    public func clearFilters() { filters = ProjectFilterSet() }

    func passesFilters(_ p: Project) -> Bool {
        let f = filters
        if !f.kinds.isEmpty && !f.kinds.contains(where: { $0.matches(p) }) { return false }
        if !f.frameworks.isEmpty && !p.targets.contains(where: { f.frameworks.contains($0.framework ?? "") }) { return false }
        switch f.git {
        case .any: break
        case .changes: if (gitBadges[p.id]?.changes ?? 0) == 0 { return false }
        case .clean: if let badge = gitBadges[p.id], !badge.isClean { return false }
        }
        if f.onlyRunning && !isRunning(p) { return false }
        if f.onlyPinned && !isPinned(p) { return false }
        return true
    }

    /// Ids of apps that live inside a collection.
    var appsInCollections: Set<String> {
        func walk(_ nodes: [ProjectNode], inside: Bool) -> [String] {
            nodes.flatMap { n -> [String] in
                let mine = inside ? (n.project.map { [$0.id] } ?? []) : []
                return mine + walk(n.children, inside: inside || n.kind == .collection)
            }
        }
        return Set(walk(tree, inside: false))
    }
}
