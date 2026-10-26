import Foundation
import NexCore

extension AppModel {
    public func tasks(for project: Project) -> [ProjectTask] { tasks.filter { $0.projectID == project.id } }
    public var openTaskCount: Int { tasks.filter { !$0.isDone }.count }

    @discardableResult
    public func addTask(title: String, notes: String, project: Project) -> ProjectTask? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let task = taskStore.add(title: trimmed, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines), projectID: project.id, projectName: project.name)
        tasksChanged()
        return task
    }

    public func setTaskDone(_ task: ProjectTask, _ done: Bool) {
        taskStore.setDone(task.id, done)
        tasksChanged()
    }

    public func deleteTask(_ task: ProjectTask) {
        taskStore.delete(task.id)
        tasksChanged()
    }

    public func renameTask(_ task: ProjectTask, title: String, notes: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        taskStore.rename(task.id, title: trimmed, notes: notes)
        tasksChanged()
    }

    private func tasksChanged() {
        tasks = taskStore.tasks
        publishSnapshot()          // the Tasks widget shows what's done and what's open
    }
}
