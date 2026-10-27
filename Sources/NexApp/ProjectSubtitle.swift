import Foundation
import NexCore

/// "Full-stack · Next.js + Django": the line under a project's name, on every platform.
public enum ProjectSubtitle {
    public static func text(for project: Project) -> String {
        let kinds = ServiceKind.allCases.filter { k in project.targets.contains { $0.kind == k } }
        func fw(_ kind: ServiceKind) -> String? { project.targets.first { $0.kind == kind }?.framework }
        if project.isFullStack {
            let names = [fw(.frontend), fw(.backend)].compactMap { $0 }
            return names.isEmpty ? "Full-stack" : "Full-stack · " + names.joined(separator: " + ")
        }
        let titles = kinds.map { $0.rawValue.capitalized }.joined(separator: " + ")
        if kinds.count == 1, let name = fw(kinds[0]), name != titles { return "\(titles) · \(name)" }
        return titles
    }
}
