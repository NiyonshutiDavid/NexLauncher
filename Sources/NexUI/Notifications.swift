import Foundation
import UserNotifications
import NexCore
import NexProcess

public enum NotificationAuthorization: Equatable, Sendable { case notDetermined, denied, authorized }

public enum NotificationEvent: Equatable, Sendable {
    case serviceReady(project: String, projectID: String, kind: ServiceKind, port: Int)
    case serviceCrashed(project: String, projectID: String, kind: ServiceKind, reason: String)
    case projectAdded(name: String, path: String, cloned: Bool)
    case agentFinished(project: String, projectID: String, agent: String, success: Bool, summary: String)
}

public struct NotificationRequest: Equatable, Sendable {
    public let title: String
    public let body: String
    public let projectID: String?
    public let openURL: String?
}

public struct NotificationPrefs: Equatable, Sendable {
    public var enabled: Bool
    public var ready: Bool
    public var crash: Bool
    public var added: Bool
    public var onlyInBackground: Bool
    public var agents: Bool = true
}

/// Decides which events become notifications and what they say. Pure, so it is easy to test.
public enum NotificationPlanner {
    public static func request(for event: NotificationEvent, prefs: NotificationPrefs, appIsActive: Bool) -> NotificationRequest? {
        guard prefs.enabled else { return nil }
        if prefs.onlyInBackground && appIsActive { return nil }
        switch event {
        case .serviceReady(let project, let id, let kind, let port):
            guard prefs.ready else { return nil }
            return NotificationRequest(title: "\(project) is ready", body: "\(kind.rawValue.capitalized) is running on localhost:\(port).",
                                       projectID: id, openURL: "http://localhost:\(port)")
        case .serviceCrashed(let project, let id, let kind, let reason):
            guard prefs.crash else { return nil }
            return NotificationRequest(title: "\(project) stopped unexpectedly", body: "\(kind.rawValue.capitalized): \(reason)",
                                       projectID: id, openURL: nil)
        case .projectAdded(let name, let path, let cloned):
            guard prefs.added else { return nil }
            return NotificationRequest(title: "\(name) was \(cloned ? "cloned" : "created")", body: "It's in your projects folder, ready to open.",
                                       projectID: path, openURL: nil)
        case .agentFinished(let project, let id, let agent, let success, let summary):
            guard prefs.agents else { return nil }
            let body = summary.isEmpty ? (success ? "The task is done." : "It stopped before finishing.") : String(summary.prefix(180))
            return NotificationRequest(title: success ? "\(agent) finished in \(project)" : "\(agent) couldn't finish in \(project)",
                                       body: body, projectID: id, openURL: nil)
        }
    }

    /// Turns changes in service state into events: ready when a port first appears, crashed when a running
    /// service fails. A stop the user asked for ends as `.stopped` and stays silent.
    public static func events(previous: [ServiceID: ServiceState], current: [ServiceID: ServiceState], projects: [Project]) -> [NotificationEvent] {
        var out: [NotificationEvent] = []
        for (id, state) in current {
            guard let project = projects.first(where: { $0.id == id.projectID }) else { continue }
            let before = previous[id]
            switch state {
            case .running(let port?):
                if case .running(let old?) = before, old == port { continue }
                if case .running(let old?) = before, old != port { continue }       // first port wins; later changes are noise
                out.append(.serviceReady(project: project.name, projectID: project.id, kind: id.kind, port: port))
            case .failed(let reason):
                guard before?.isActive == true else { continue }
                out.append(.serviceCrashed(project: project.name, projectID: project.id, kind: id.kind, reason: reason))
            default: break
            }
        }
        return out
    }
}

public protocol Notifying: Sendable {
    func authorizationStatus() async -> NotificationAuthorization
    func requestAuthorization() async -> Bool
    func post(_ request: NotificationRequest) async
}

/// Delivers through macOS. Does nothing outside an .app bundle (tests, `swift run`), where the framework would trap.
public final class SystemNotifier: Notifying, @unchecked Sendable {
    public static let readyCategory = "nexlauncher.ready"
    public static let openBrowserAction = "nexlauncher.open-browser"

    public init() {}

    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleURL.pathExtension == "app" ? UNUserNotificationCenter.current() : nil
    }

    /// Registers the "Open in browser" action; call once at launch.
    public func registerCategories() {
        let open = UNNotificationAction(identifier: Self.openBrowserAction, title: "Open in browser", options: [.foreground])
        center?.setNotificationCategories([UNNotificationCategory(identifier: Self.readyCategory, actions: [open], intentIdentifiers: [])])
    }

    public func authorizationStatus() async -> NotificationAuthorization {
        guard let center else { return .notDetermined }
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        default: return .notDetermined
        }
    }

    public func requestAuthorization() async -> Bool {
        guard let center else { return false }
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    public func post(_ request: NotificationRequest) async {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        var info: [String: String] = [:]
        if let id = request.projectID { info["projectID"] = id }
        if let url = request.openURL { info["openURL"] = url; content.categoryIdentifier = Self.readyCategory }
        content.userInfo = info
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
