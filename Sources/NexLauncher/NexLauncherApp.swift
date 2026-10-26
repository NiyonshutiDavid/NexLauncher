import SwiftUI
import AppKit
import NexUI
import UserNotifications

@main
struct NexLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private var model: AppModel { delegate.model }
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("NexLauncher", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 960, minHeight: 640)
                .onOpenURL { url in Task { await model.handle(url: url) } }
                .task {
                    model.openMainWindowAction = { openWindow(id: "main") }
                    model.applyDockIconPolicy()
                    await model.refresh()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)       // the title bar is hidden: drag the window by its background
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            SettingsCommands(model: model)
        }

    }
}

/// ⌘, opens Settings inside the main window, reopening the window if it was closed.
struct SettingsCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                model.page = .settings(.general)
                model.showMainWindow()
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Owned here (not by a window) so Quit can always see running services and terminals, even with no window open.
    let model = AppModel()
    private var statusBar: StatusBarController?

    /// The notification delegate must be in place before launch finishes, or a click that launched the app is lost.
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        UNUserNotificationCenter.current().delegate = self
        (model.notifier as? SystemNotifier)?.registerCategories()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController(model: model)        // menu bar item + ⌥⌘L quick panel
        Task { await model.refreshNotificationStatus() }
    }

    @objc func showQuickPanel() { statusBar?.togglePanel() }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let projectID = info["projectID"] as? String
        let url = (info["openURL"] as? String).flatMap(URL.init(string:))
        let action = response.actionIdentifier
        await MainActor.run {
            if action == SystemNotifier.openBrowserAction, let url { NSWorkspace.shared.open(url); return }
            if let projectID { model.openFromNotification(projectID: projectID) }
            model.showMainWindow()
        }
    }

    /// Right-clicking the Dock icon lists pinned projects with one-click Run/Stop.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let entries = PinnedMenu.entries(pinned: model.pinnedProjects, isRunning: { model.isRunning($0) })
        if entries.isEmpty {
            let hint = NSMenuItem(title: "Pin projects in NexLauncher to list them here", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        } else {
            for entry in entries {
                let item = NSMenuItem(title: entry.title, action: #selector(dockToggle(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry.id
                item.image = NSImage(systemSymbolName: entry.isRunning ? "stop.fill" : "play.fill", accessibilityDescription: nil)
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        let quick = NSMenuItem(title: "Quick Panel (⌥⌘L)", action: #selector(showQuickPanel), keyEquivalent: "")
        quick.target = self
        menu.addItem(quick)
        return menu
    }

    @objc private func dockToggle(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String, let project = model.project(id: id) else { return }
        Task { await model.toggleRun(project) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let services = model.processes.runningCount
        let terminalBusy = model.terminals.anyForegroundProgram
        guard services > 0 || terminalBusy else {
            model.terminals.closeAll()
            return .terminateNow
        }
        let alert = NSAlert()
        var parts: [String] = []
        if services > 0 { parts.append("\(services) service\(services == 1 ? "" : "s") still running") }
        if terminalBusy { parts.append("a program is still running in a terminal") }
        alert.messageText = parts.joined(separator: " and ").prefix(1).uppercased() + parts.joined(separator: " and ").dropFirst()
        alert.informativeText = "Quit and stop everything, or keep running from the menu bar."
        alert.addButton(withTitle: "Stop and Quit")
        alert.addButton(withTitle: "Keep Running in Menu Bar")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task {
                await model.stopAllServices()
                model.terminals.closeAll()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        case .alertSecondButtonReturn:
            sender.windows.forEach { $0.close() }
            return .terminateCancel
        default:
            return .terminateCancel
        }
    }
}
