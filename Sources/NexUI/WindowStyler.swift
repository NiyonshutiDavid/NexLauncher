import SwiftUI
import AppKit

/// Reaches the hosting NSWindow: transparent title bar with no separator. In full screen macOS draws the toolbar
/// on an opaque bar, so it is hidden there and `isFullScreen` tells the pages to draw their header controls
/// themselves.
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
        let binding = $isFullScreen
        let center = NotificationCenter.default
        coordinator.observers = [
            center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { _ in
                window.toolbar?.isVisible = false
                MainActor.assumeIsolated { binding.wrappedValue = true }
            },
            center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { _ in
                window.toolbar?.isVisible = true
                MainActor.assumeIsolated { binding.wrappedValue = false }
            },
        ]
        if window.styleMask.contains(.fullScreen) {
            window.toolbar?.isVisible = false
            isFullScreen = true
        }
        // Developer option for screenshots: `-NexFullScreen YES`.
        if UserDefaults.standard.bool(forKey: "NexFullScreen"), !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }
}
