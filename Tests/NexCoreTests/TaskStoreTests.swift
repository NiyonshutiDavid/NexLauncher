import Testing
import Foundation
@testable import NexCore

@Suite struct TaskStoreTests {
    private func store(_ t: TempTree) -> TaskStore { TaskStore(fileURL: t.root.appendingPathComponent("tasks.json")) }

    @Test func addedTasksPersist() {
        let t = TempTree()
        let s = store(t)
        let task = s.add(title: "Fix login", notes: "Safari only", projectID: "/p/A", projectName: "A")
        #expect(task.title == "Fix login" && !task.isDone)
        let reloaded = store(t)
        #expect(reloaded.tasks.map(\.title) == ["Fix login"])
        #expect(reloaded.tasks[0].notes == "Safari only")
    }

    @Test func completingSetsTheDateAndCanBeUndone() {
        let t = TempTree()
        let s = store(t)
        let task = s.add(title: "Ship", notes: "", projectID: "/p/A", projectName: "A")
        s.setDone(task.id, true)
        #expect(s.tasks[0].isDone && s.tasks[0].doneAt != nil)
        s.setDone(task.id, false)
        #expect(!s.tasks[0].isDone && s.tasks[0].doneAt == nil)
    }

    @Test func deleteAndRename() {
        let t = TempTree()
        let s = store(t)
        let a = s.add(title: "One", notes: "", projectID: "/p/A", projectName: "A")
        let b = s.add(title: "Two", notes: "", projectID: "/p/A", projectName: "A")
        s.rename(a.id, title: "First", notes: "n")
        s.delete(b.id)
        #expect(store(t).tasks.map(\.title) == ["First"])
        #expect(store(t).tasks[0].notes == "n")
    }

    @Test func recentlyDoneIsNewestFirstAndLimited() {
        let t = TempTree()
        let s = store(t)
        let ids = (1...5).map { s.add(title: "T\($0)", notes: "", projectID: "/p", projectName: "P").id }
        for (i, id) in ids.enumerated() { s.setDone(id, true, at: Date(timeIntervalSince1970: Double(i))) }
        #expect(s.recentlyDone(limit: 3).map(\.title) == ["T5", "T4", "T3"])
        #expect(s.openCount == 0)
    }

    @Test func corruptFileStartsEmpty() {
        let t = TempTree()
        t.write("tasks.json", "{nope")
        #expect(store(t).tasks.isEmpty)
    }

    @Test func tasksForAProject() {
        let t = TempTree()
        let s = store(t)
        _ = s.add(title: "A1", notes: "", projectID: "/p/A", projectName: "A")
        _ = s.add(title: "B1", notes: "", projectID: "/p/B", projectName: "B")
        #expect(s.tasks(for: "/p/A").map(\.title) == ["A1"])
    }

    @Test func snapshotFromOlderBuildsStillDecodes() throws {
        let old = #"{"running":[],"pinned":[]}"#
        let snap = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(old.utf8))
        #expect(snap.tasks.isEmpty && snap.openTaskCount == 0)
    }
}
