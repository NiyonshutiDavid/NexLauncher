import Foundation
import Adwaita
import CAdw
import NexApp

/// Desktop notifications through GApplication (the notification portal inside a Flatpak).
final class LinuxNotifier: Notifying, @unchecked Sendable {
    let app: AdwaitaApp

    init(app: AdwaitaApp) { self.app = app }

    func authorizationStatus() async -> NotificationAuthorization { .authorized }
    func requestAuthorization() async -> Bool { true }

    func post(_ request: NotificationRequest) async {
        await MainActor.run {
            guard let notification = g_notification_new(request.title) else { return }
            g_notification_set_body(notification, request.body)
            g_application_send_notification(OpaquePointer(app.pointer), nil, notification)
            g_object_unref(notification)
        }
    }
}
