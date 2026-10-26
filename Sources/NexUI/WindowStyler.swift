import SwiftUI
import AppKit

/// Reaches the hosting NSWindow: transparent title bar with no separator, and the (empty) toolbar shown only in
/// a normal window — it keeps the window controls there — and hidden in full screen, where macOS would draw it
/// as an opaque strip above the page's own fading header.
struct WindowStyler: NSViewRepresentable {
    final class Coordinator {
        var observers: [NSObjectProtocol] = []
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { style(view.window, context.coordinator) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func style(_ window: NSWindow?, _ coordinator: Coordinator) {
        guard let window, coordinator.observers.isEmpty else { return }
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        let center = NotificationCenter.default
        coordinator.observers = [
            center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { _ in
                window.toolbar?.isVisible = false
            },
            center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { _ in
                window.toolbar?.isVisible = true
            },
        ]
        if window.styleMask.contains(.fullScreen) { window.toolbar?.isVisible = false }
    }
}
