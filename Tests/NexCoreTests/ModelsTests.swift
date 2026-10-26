import Testing
import Foundation
@testable import NexCore

private func target(_ kind: ServiceKind) -> ServiceTarget {
    ServiceTarget(kind: kind, directory: URL(fileURLWithPath: "/tmp/x"), framework: nil, command: "")
}

private func date(hour: Int) -> (Date, Calendar) {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let d = cal.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: hour))!
    return (d, cal)
}

@Suite struct ModelsTests {
    @Test func fullStackWhenFrontendAndBackend() {
        let p = Project(id: "a", name: "A", root: URL(fileURLWithPath: "/tmp/a"), targets: [target(.frontend), target(.backend)])
        #expect(p.isFullStack)
    }
    @Test func notFullStackWithFrontendOnly() {
        let p = Project(id: "a", name: "A", root: URL(fileURLWithPath: "/tmp/a"), targets: [target(.frontend)])
        #expect(!p.isFullStack)
    }
    @Test(arguments: [(9, "Good morning, David"), (14, "Good afternoon, David"), (19, "Good evening, David"), (23, "Good night, David"), (3, "Good night, David")])
    func greeting(hour: Int, expected: String) {
        let (d, cal) = date(hour: hour)
        #expect(Greeter.greeting(for: d, name: "David", calendar: cal) == expected)
    }
}
