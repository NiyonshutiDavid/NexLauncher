import SwiftUI
import AppKit

/// Reaches the hosting NSWindow: transparent title bar with no separator. The toolbar (which holds each page's
/// header controls) stays visible in full screen too; its background is hidden in ContentView.
struct WindowStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { style(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func style(_ window: NSWindow?) {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        // Developer option for screenshots: `-NexFullScreen YES`.
        if UserDefaults.standard.bool(forKey: "NexFullScreen"), !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }
}
