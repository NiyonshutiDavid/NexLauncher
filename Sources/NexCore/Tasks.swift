import Foundation

public struct ProjectTask: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var projectID: String
    public var projectName: String
    public var title: String
    public var notes: String
    public let createdAt: Date
    public var doneAt: Date?

    public var isDone: Bool { doneAt != nil }
}

/// Per-project to-dos, stored as JSON in the app's support folder (the widget reads the summary from the snapshot).
public final class TaskStore: @unchecked Sendable {
    public private(set) var tasks: [ProjectTask]
    private let fileURL: URL

    public static var defaultURL: URL { AppSettings.supportDirectory.appendingPathComponent("tasks.json") }

    public init(fileURL: URL = TaskStore.defaultURL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL), let decoded = try? JSONDecoder().decode([ProjectTask].self, from: data) {
            tasks = decoded
        } else {
            tasks = []
        }
    }

    @discardableResult
    public func add(title: String, notes: String, projectID: String, projectName: String) -> ProjectTask {
        let task = ProjectTask(id: UUID(), projectID: projectID, projectName: projectName, title: title, notes: notes, createdAt: Date(), doneAt: nil)
        tasks.append(task)
        save()
        return task
    }

    public func setDone(_ id: UUID, _ done: Bool, at date: Date = Date()) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].doneAt = done ? date : nil
        save()
    }

    public func rename(_ id: UUID, title: String, notes: String) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].title = title
        tasks[i].notes = notes
        save()
    }

    public func delete(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        save()
    }

    public func tasks(for projectID: String) -> [ProjectTask] { tasks.filter { $0.projectID == projectID } }
    public var openCount: Int { tasks.filter { !$0.isDone }.count }

    public func recentlyDone(limit: Int) -> [ProjectTask] {
        Array(tasks.filter(\.isDone).sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }.prefix(limit))
    }

    private func save() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(tasks) { try? data.write(to: fileURL, options: .atomic) }
    }
}
