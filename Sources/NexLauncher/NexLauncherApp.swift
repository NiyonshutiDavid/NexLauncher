import SwiftUI
import AppKit
import NexUI

@main
struct NexLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("NexLauncher", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 860, minHeight: 560)
                .task {
                    delegate.model = model
                    model.applyDockIconPolicy()
                    await model.refresh()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)

        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Image(systemName: "bolt.horizontal.circle.fill")
            if !model.menuBarTitle.isEmpty { Text(model.menuBarTitle) }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.shouldConfirmQuit else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "\(model.processes.runningCount) service(s) still running"
        alert.informativeText = "Quit and stop them, or keep them running from the menu bar."
        alert.addButton(withTitle: "Stop and Quit")
        alert.addButton(withTitle: "Keep Running in Menu Bar")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task {
                await model.stopAllServices()
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
