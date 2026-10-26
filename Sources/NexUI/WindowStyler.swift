import SwiftUI
import AppKit

/// Reaches the hosting NSWindow to make the title bar transparent with no separator, so the toolbar floats over
/// the content (also in full screen, where SwiftUI's toolbar-background setting isn't applied).
struct WindowStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { style(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { style(nsView.window) }
    }

    private func style(_ window: NSWindow?) {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
    }
}
