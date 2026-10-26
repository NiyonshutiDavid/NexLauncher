import SwiftUI
import AppKit
import NexUI

@main
struct NexLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private var model: AppModel { delegate.model }

    var body: some Scene {
        WindowGroup("NexLauncher", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 960, minHeight: 640)
                .onOpenURL { url in Task { await model.handle(url: url) } }
                .task {
                    model.applyDockIconPolicy()
                    await model.refresh()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    model.page = .settings(.general)
                    NSApp.activate()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarContent(model: model)
                .nexTheme(model.settings.settings.theme, appearance: model.settings.settings.appearance)
        } label: {
            Image(systemName: "bolt.horizontal.circle.fill")
            if !model.menuBarTitle.isEmpty { Text(model.menuBarTitle) }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Owned here (not by a window) so Quit can always see running services and terminals, even with no window open.
    let model = AppModel()

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
