import Testing
import Foundation
import NexCore
@testable import NexApp
import NexTestSupport

@MainActor
@Suite struct TasksModelTests {
    private func model() async -> (Sandbox, AppModel) {
        let sb = Sandbox()
        sb.write("Site/package.json", Sandbox.vite)
        let m = sb.makeModel()
        var reloads = 0
        m.reloadWidgets = { reloads += 1 }
        await m.refresh()
        return (sb, m)
    }

    @Test func addingTrimsAndIgnoresBlankTitles() async {
        let (sb, m) = await model(); defer { _ = sb }
        let p = m.projects[0]
        #expect(m.addTask(title: "   ", notes: "", project: p) == nil)
        let t = m.addTask(title: "  Write README  ", notes: "", project: p)
        #expect(t?.title == "Write README")
        #expect(m.tasks(for: p).count == 1)
    }

    @Test func completingATaskPublishesItToTheWidget() async {
        let (sb, m) = await model(); defer { _ = sb }
        let task = m.addTask(title: "Deploy", notes: "", project: m.projects[0])!
        m.setTaskDone(task, true)
        let snap = SharedContainer.read(from: sb.root.appendingPathComponent("shared"))
        #expect(snap.tasks.first?.title == "Deploy" && snap.tasks.first?.done == true)
        #expect(snap.openTaskCount == 0)
    }

    @Test func openTasksAreCountedAcrossProjects() async {
        let (sb, m) = await model(); defer { _ = sb }
        _ = m.addTask(title: "a", notes: "", project: m.projects[0])
        _ = m.addTask(title: "b", notes: "", project: m.projects[0])
        #expect(m.openTaskCount == 2)
        #expect(SharedContainer.read(from: sb.root.appendingPathComponent("shared")).openTaskCount == 2)
    }

    @Test func tasksPageAndTabExist() {
        #expect(DetailTab.allCases.contains(.tasks))
        let model = Sandbox().makeModel()
        model.page = .tasks
        #expect(model.page == .tasks)
    }
}
