import AppKit
import SwiftUI
import Carbon.HIToolbox
import Observation
import NexUI

/// The menu bar item and its panel. Built on NSStatusItem (not MenuBarExtra) so the same panel can also be
/// opened with a keyboard shortcut — macOS hides status items when the menu bar is full (common with a notch).
@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var fallbackPanel: NSPanel?
    private var hotKey: HotKey?

    init(model: AppModel) {
        self.model = model
        super.init()
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "bolt.horizontal.circle.fill", accessibilityDescription: "NexLauncher")
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePanel)
        }
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: panelContent())
        observeTitle()
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(cmdKey | optionKey)) { [weak self] in self?.togglePanel() }
    }

    private func panelContent() -> some View {
        PanelRoot(model: model)
    }

    /// Keeps the running count next to the icon, re-arming observation after each change.
    private func observeTitle() {
        withObservationTracking {
            item.button?.title = model.menuBarTitle.isEmpty ? "" : " \(model.menuBarTitle)"
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeTitle() }
        }
    }

    /// Whether the status item is actually on screen (macOS hides overflow items).
    private var itemIsVisible: Bool {
        guard let window = item.button?.window, window.occlusionState.contains(.visible) else { return false }
        return NSScreen.screens.contains { $0.frame.intersects(window.frame) && window.frame.minY < $0.frame.maxY }
    }

    @objc func togglePanel() {
        if popover.isShown { popover.performClose(nil); return }
        if let panel = fallbackPanel, panel.isVisible { panel.orderOut(nil); return }
        if itemIsVisible, let button = item.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        } else {
            showFallbackPanel()
        }
    }

    /// The same panel as a floating window under the top-right of the screen, for when the icon is hidden.
    private func showFallbackPanel() {
        let panel = fallbackPanel ?? {
            let p = KeyablePanel(contentRect: .zero, styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
            p.titleVisibility = .hidden
            p.titlebarAppearsTransparent = true
            p.isFloatingPanel = true
            p.level = .statusBar
            p.hidesOnDeactivate = false
            p.isMovableByWindowBackground = true
            p.contentViewController = NSHostingController(rootView: panelContent())
            p.standardWindowButton(.closeButton)?.isHidden = true
            p.standardWindowButton(.miniaturizeButton)?.isHidden = true
            p.standardWindowButton(.zoomButton)?.isHidden = true
            fallbackPanel = p
            return p
        }()
        panel.layoutIfNeeded()
        if let screen = NSScreen.main {
            let size = panel.contentViewController?.view.fittingSize ?? NSSize(width: 360, height: 400)
            let visible = screen.visibleFrame
            panel.setFrame(NSRect(x: visible.maxX - size.width - 12, y: visible.maxY - size.height - 8, width: size.width, height: size.height), display: true)
        }
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak panel] _ in
            Task { @MainActor in panel?.orderOut(nil) }
        }
    }
}

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Applies the user's theme to the panel content.
private struct PanelRoot: View {
    @Bindable var model: AppModel
    var body: some View {
        MenuBarContent(model: model)
            .nexTheme(model.settings.settings.theme, appearance: model.settings.settings.appearance)
    }
}

/// A system-wide shortcut through Carbon's RegisterEventHotKey (no accessibility permission needed).
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private let id: UInt32

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        id = HotKey.nextID
        HotKey.nextID += 1
        HotKey.actions[id] = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async { HotKey.actions[id]?() }
            return noErr
        }, 1, &spec, nil, &handler)
        RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: OSType(0x4E584C48), id: id), GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        HotKey.actions[id] = nil
    }
}
