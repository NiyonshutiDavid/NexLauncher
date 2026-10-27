import Foundation
import NexCore

/// What the app model asks of the system it runs on. The Mac app implements it with AppKit, the Linux app with
/// GTK and desktop portals; tests record the calls.
@MainActor
public protocol PlatformServices: AnyObject {
    func open(_ url: URL)
    func reveal(_ path: URL)
    func copy(_ text: String)
    func open(_ files: [URL], withApplicationAt app: URL)
    /// Brings an existing main window forward; false when there is none to show.
    @discardableResult func activateMainWindow() -> Bool
    func reloadWidgets()
    /// No-op where there's no Dock.
    func setDockIconVisible(_ visible: Bool)
    var isAppActive: Bool { get }
}

/// Terminal tabs (SwiftTerm on macOS, VTE on Linux).
@MainActor
public protocol TerminalHost: AnyObject {
    var hasRunningPrograms: Bool { get }
    /// Opens a tab at `directory`, optionally typing `command` into it, and returns its id.
    @discardableResult func openTab(at directory: URL, command: String?) -> UUID
    func close(_ id: UUID)
    func closeAll()
}
