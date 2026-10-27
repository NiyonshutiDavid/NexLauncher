import SwiftUI

/// Closes the pop-up a view is shown in (the in-window replacement for a sheet's `dismiss`).
struct ModalCloseAction {
    var action: () -> Void = {}
    func callAsFunction() { action() }
}

extension EnvironmentValues {
    @Entry var closeModal = ModalCloseAction()
    /// A pop-up covers the window: pages draw their header controls under its dimming instead of in the toolbar.
    @Entry var modalIsOpen = false
}

/// Any pop-up content presented over the whole window (e.g. the git name and email form).
public struct ModalContent: Identifiable {
    public let id = UUID()
    let view: AnyView
    init<V: View>(_ view: V) { self.view = AnyView(view) }
}

/// Pop-ups drawn inside the window rather than as system sheets: in full screen macOS reveals its opaque title
/// bar for every sheet, which shows up as an empty bar above the page.
struct ModalLayer<Content: View>: View {
    @Environment(\.theme) private var theme
    let onClose: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}                     // modal: clicks outside don't reach the page
                .transition(.opacity)
            content
                .background(theme.canvas, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(theme.line))
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 40, y: 18)
                .environment(\.closeModal, ModalCloseAction(action: onClose))
                .onExitCommand(perform: onClose)
                .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
    }
}
