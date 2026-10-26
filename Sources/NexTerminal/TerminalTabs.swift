import Foundation
import Observation

@MainActor @Observable
public final class TerminalTabs {
    public private(set) var sessions: [TerminalSession] = []
    public var selectedID: UUID?

    public init() {}

    /// Opens (and starts) a new tab at `directory` and selects it.
    @discardableResult
    public func open(at directory: URL) -> TerminalSession {
        let session = TerminalSession(directory: directory)
        sessions.append(session)
        selectedID = session.id
        session.start()
        return session
    }

    public func close(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].terminate()
        sessions.remove(at: index)
        if selectedID == id { selectedID = sessions.last?.id }
    }

    public var anyForegroundProgram: Bool { sessions.contains { $0.hasForegroundProgram } }

    public func closeAll() {
        sessions.forEach { $0.terminate() }
        sessions.removeAll()
        selectedID = nil
    }
}
