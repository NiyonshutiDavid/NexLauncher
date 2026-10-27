import Foundation
import NexCore
import NexGit
import NexProcess

public enum QuickGitAction: Sendable {
    case fetch, pull, push
    var progressive: String {
        switch self {
        case .fetch: return "Fetching"
        case .pull: return "Pulling"
        case .push: return "Pushing"
        }
    }
    var pastTense: String {
        switch self {
        case .fetch: return "Fetched"
        case .pull: return "Pulled"
        case .push: return "Pushed"
        }
    }
}

public struct QuickGitReport: Equatable, Sendable {
    public let success: Bool
    public let message: String
}

public struct StatusMessage: Equatable, Identifiable, Sendable {
    public let id = UUID()
    public let text: String
    public let isError: Bool
    public init(text: String, isError: Bool) { self.text = text; self.isError = isError }
}

public enum MenuBarFilter {
    public static func matching(_ query: String, in projects: [Project]) -> [Project] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? projects : projects.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }
}

extension AppModel {
    // MARK: - Running services (for the menu bar)

    public func runningPorts(for project: Project) -> [Int] {
        Set(processes.states.compactMap { id, state -> Int? in
            guard id.projectID == project.id, case .running(let port?) = state else { return nil }
            return port
        }).sorted()
    }

    public var runningProjects: [Project] { projects.filter { isRunning($0) } }

    // MARK: - Quick git actions (fetch / pull / push across the project's repositories)

    public func isGitBusy(_ project: Project) -> Bool { gitBusy.contains(project.id) }

    /// Runs the action on every repository of the project. A failure doesn't stop the others; the report
    /// names each repository that failed, and the badges are refreshed either way.
    @discardableResult
    public func quickGit(_ action: QuickGitAction, project: Project) async -> QuickGitReport {
        let repos = git.findRepos(under: project.root)
        guard !repos.isEmpty else { return report(.init(success: false, message: "\(project.name) isn't a git repository.")) }
        guard !gitBusy.contains(project.id) else { return report(.init(success: false, message: "\(project.name) is still busy with git.")) }
        gitBusy.insert(project.id)
        statusMessage = StatusMessage(text: "\(action.progressive) \(project.name)…", isError: false)
        var failures: [String] = []
        for repo in repos {
            do {
                switch action {
                case .fetch: try await git.fetch(repo)
                case .pull: try await git.pull(repo, strategy: settings.settings.defaultPullStrategy.strategy)
                case .push: try await git.push(repo)
                }
            } catch {
                let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                failures.append((repos.count > 1 ? "\(project.name) (\(repo.lastPathComponent))" : project.name) + ": " + reason)
            }
        }
        gitBusy.remove(project.id)
        await refreshGitBadges()
        if !failures.isEmpty { return report(.init(success: false, message: failures.joined(separator: "\n"))) }
        let suffix = repos.count > 1 ? " (\(repos.count) repositories)" : ""
        return report(.init(success: true, message: "\(action.pastTense) \(project.name)\(suffix)."))
    }

    private func report(_ r: QuickGitReport) -> QuickGitReport {
        let message = StatusMessage(text: r.message, isError: !r.success)
        statusMessage = message
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            if self?.statusMessage?.id == message.id { self?.statusMessage = nil }
        }
        return r
    }

    public func dismissStatusMessage() { statusMessage = nil }
}
