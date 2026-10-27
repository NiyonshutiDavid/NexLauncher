import SwiftUI
import AppKit

/// Reaches the hosting NSWindow: transparent title bar with no separator. In full screen the toolbar only shows on
/// hover (on macOS's own opaque bar), so `isFullScreen` tells the pages to draw their header controls themselves.
struct WindowStyler: NSViewRepresentable {
    @Binding var isFullScreen: Bool

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
        window.isMovableByWindowBackground = true     // the title bar is hidden: drag the window by its background
        let binding = $isFullScreen
        let center = NotificationCenter.default
        coordinator.observers = [
            center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { binding.wrappedValue = true }
            },
            center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { binding.wrappedValue = false }
            },
        ]
        if window.styleMask.contains(.fullScreen) { isFullScreen = true }
        // Developer option for screenshots: `-NexFullScreen YES`.
        if UserDefaults.standard.bool(forKey: "NexFullScreen") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {   // once the window is on screen
                if !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
            }
        }
    }
}
