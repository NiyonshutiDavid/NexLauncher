import Foundation
import NexCore
import NexProcess

extension AppModel {
    var notificationPrefs: NotificationPrefs {
        let s = settings.settings
        return NotificationPrefs(enabled: s.notificationsEnabled, ready: s.notifyReady, crash: s.notifyCrash,
                                 added: s.notifyAdded, onlyInBackground: s.notifyOnlyInBackground, agents: s.notifyAgents)
    }

    /// Called on every service state change: posts "ready" and "stopped unexpectedly" notifications.
    func processStatesChanged() {
        let current = processes.states
        let events = NotificationPlanner.events(previous: lastServiceStates, current: current, projects: projects)
        lastServiceStates = current
        for event in events { post(event) }
    }

    func post(_ event: NotificationEvent) {
        guard let request = NotificationPlanner.request(for: event, prefs: notificationPrefs, appIsActive: appIsActive()) else { return }
        let notifier = notifier
        Task { await notifier.post(request) }
    }

    public func refreshNotificationStatus() async {
        notificationStatus = await notifier.authorizationStatus()
    }

    /// Turning on asks macOS for permission; the switch stays off if it is refused.
    public func setNotificationsEnabled(_ on: Bool) async {
        guard on else {
            settings.settings.notificationsEnabled = false
            settings.save()
            return
        }
        var status = await notifier.authorizationStatus()
        if status == .notDetermined { _ = await notifier.requestAuthorization(); status = await notifier.authorizationStatus() }
        notificationStatus = status
        settings.settings.notificationsEnabled = status == .authorized
        settings.save()
    }

    public func sendTestNotification() async {
        if await notifier.authorizationStatus() == .notDetermined { _ = await notifier.requestAuthorization() }
        notificationStatus = await notifier.authorizationStatus()
        await notifier.post(NotificationRequest(title: "NexLauncher notifications work",
                                                body: "You'll hear from me when a service is ready or stops unexpectedly.",
                                                projectID: nil, openURL: nil))
    }

    /// A notification was clicked: show that project (or folder).
    public func openFromNotification(projectID: String) {
        if project(id: projectID) != nil {
            page = .project(projectID)
            detailTab = .overview
        } else if FileManager.default.fileExists(atPath: projectID) {
            page = .folder(projectID)
            detailTab = .overview
        }
    }
}
