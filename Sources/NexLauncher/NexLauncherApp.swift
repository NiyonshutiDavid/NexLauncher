import SwiftUI
import AppKit
import NexUI
import UserNotifications

@main
struct NexLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private var model: AppModel { delegate.model }
    @Environment(\.openWindow) private var openWindow

    /// Developer option for screenshots: `open NexLauncher.app --args -NexStartPage ai|tasks|flutter|running|pinned|settings`,
    /// `add-project` / `widgets-how-to` (sheets), or `project:<name>` / `project-ai:<name>` (after the scan) for a project page, optionally with its AI panel open.
    private func openStartPage() {
        switch UserDefaults.standard.string(forKey: "NexStartPage") {
        case "ai": model.page = .ai
        case "tasks": model.page = .tasks
        case "settings": model.page = .settings(.ai)
        case "flutter": model.select(filter: .flutter)
        case "running": model.select(filter: .running)
        case "pinned": model.select(filter: .pinned)
        case "add-project": model.sheet = .addProject(.newFolder)
        case "widgets-how-to": model.sheet = .widgetsHowTo
        case let value? where value.hasPrefix("project"):
            let name = value.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
            guard let project = model.projects.first(where: { $0.name == name }) else { return }
            model.page = .project(project.id)
            if value.hasPrefix("project-ai:") { model.aiPanelProjectID = project.id }
        default: break
        }
    }

    var body: some Scene {
        WindowGroup("NexLauncher", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 960, minHeight: 640)
                // Full screen: the (empty) toolbar only slides in with the menu bar. Hiding it outright would make
                // macOS drop the floating sidebar below the title bar area with square-ish corners.
                .nexToolbarOnHoverInFullScreen()
                .onOpenURL { url in Task { await model.handle(url: url) } }
                .task {
                    model.openMainWindowAction = { openWindow(id: "main") }
                    model.applyDockIconPolicy()
                    openStartPage()
                    await model.refresh()
                    if UserDefaults.standard.string(forKey: "NexStartPage")?.hasPrefix("project") == true { openStartPage() }
                }
        }
        .windowStyle(.hiddenTitleBar)
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
        // Developer option for the website: `-NexExportIllustrations <dir>` writes the illustrations as PNGs and quits.
        if let dir = UserDefaults.standard.string(forKey: "NexExportIllustrations"), !dir.isEmpty {
            do { try IllustrationExporter.export(to: URL(fileURLWithPath: dir)) } catch { NSLog("Export failed: \(error)") }
            NSApp.terminate(nil)
            return
        }
        statusBar = StatusBarController(model: model)        // menu bar item + ⌃⌥⌘L quick panel
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
        let quick = NSMenuItem(title: "Quick Panel (\(AppModel.quickPanelShortcutLabel))", action: #selector(showQuickPanel), keyEquivalent: "")
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
        let agents = model.runningAgentCount
        guard services > 0 || terminalBusy || agents > 0 else {
            model.terminals.closeAll()
            return .terminateNow
        }
        let alert = NSAlert()
        var parts: [String] = []
        if services > 0 { parts.append("\(services) service\(services == 1 ? "" : "s") still running") }
        if terminalBusy { parts.append("a program is still running in a terminal") }
        if agents > 0 { parts.append("\(agents) AI agent\(agents == 1 ? " is" : "s are") still working") }
        alert.messageText = parts.joined(separator: " and ").prefix(1).uppercased() + parts.joined(separator: " and ").dropFirst()
        alert.informativeText = "Quit and stop everything, or keep running from the menu bar."
        alert.addButton(withTitle: "Stop and Quit")
        alert.addButton(withTitle: "Keep Running in Menu Bar")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task {
                await model.stopAllServices()
                await model.stopAllAgents()                  // never leave an agent editing files unsupervised
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
