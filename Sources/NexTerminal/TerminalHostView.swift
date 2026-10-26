import SwiftUI
import AppKit

/// Hosts a session's terminal view inside SwiftUI.
public struct TerminalHostView: NSViewRepresentable {
    let session: TerminalSession

    public init(session: TerminalSession) { self.session = session }

    public func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        if session.view.superview !== nsView { attach(to: nsView) }
    }

    private func attach(to container: NSView) {
        let term = session.view
        term.removeFromSuperview()
        term.frame = container.bounds
        term.autoresizingMask = [.width, .height]
        container.addSubview(term)
        DispatchQueue.main.async { term.window?.makeFirstResponder(term) }
    }
}
