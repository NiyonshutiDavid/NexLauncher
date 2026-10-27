import Foundation
import NexCore
import NexProcess

public struct SetupStep: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable { case pending, running, done, failed }
    public let id: ServiceID
    public let title: String
    public let command: String
    public var status: Status = .pending

    /// A human description of a setup command.
    public static func describe(_ command: String) -> String {
        let c = command.trimmingCharacters(in: .whitespaces)
        for pm in ["pnpm", "yarn", "bun", "npm"] where c == "\(pm) install" { return "Install packages with \(pm)" }
        if c.contains("-m venv") { return "Create a Python environment and install requirements" }
        if c == "uv sync" { return "Sync the Python environment with uv" }
        if c == "poetry install" { return "Install Python packages with Poetry" }
        if c == "composer install" { return "Install Composer packages" }
        if c == "flutter pub get" { return "Get Flutter packages" }
        if c == "dart pub get" { return "Get Dart packages" }
        if c == "bundle install" { return "Install Ruby gems" }
        if c == "mix deps.get" { return "Get Elixir dependencies" }
        if c == "dotnet restore" { return "Restore .NET packages" }
        return "Run \(c)"
    }
}

public struct SetupSession: Identifiable, Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case confirm, running, failed(String) }
    public let project: Project
    public var steps: [SetupStep]
    public var phase: Phase = .confirm
    public var id: String { project.id }

    public init(project: Project, steps: [SetupStep]) {
        self.project = project
        self.steps = steps
    }

    mutating func mark(_ id: ServiceID, _ status: SetupStep.Status) {
        if let i = steps.firstIndex(where: { $0.id == id }) { steps[i].status = status }
    }
}
