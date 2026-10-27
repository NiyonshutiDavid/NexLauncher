import Foundation
import UserNotifications
import NexCore
import NexProcess
import NexApp

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
