import SwiftUI

// NexLauncher runs on macOS 14 and later. These helpers use the macOS 26 Liquid Glass look (and macOS 15
// toolbar options) where the system has them, and plain materials and standard controls before that.

enum NexGlassStyle {
    case regular
    case tinted(Color)
}

extension View {
    /// Liquid Glass on macOS 26; a material with a hairline edge before.
    @ViewBuilder
    func nexGlass<S: Shape>(_ style: NexGlassStyle = .regular, in shape: S) -> some View {
        if #available(macOS 26, *) {
            switch style {
            case .regular: glassEffect(.regular, in: shape)
            case .tinted(let color): glassEffect(.regular.tint(color), in: shape)
            }
        } else {
            switch style {
            case .regular:
                background(shape.fill(.regularMaterial))
                    .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 1))
            case .tinted(let color):
                background(ZStack { shape.fill(.regularMaterial); shape.fill(color) })
                    .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 1))
            }
        }
    }

    /// `.glass` on macOS 26, `.bordered` before.
    @ViewBuilder
    func nexGlassButton() -> some View {
        if #available(macOS 26, *) { buttonStyle(.glass) } else { buttonStyle(.bordered) }
    }

    /// `.glassProminent` on macOS 26, `.borderedProminent` before.
    @ViewBuilder
    func nexGlassProminentButton() -> some View {
        if #available(macOS 26, *) { buttonStyle(.glassProminent) } else { buttonStyle(.borderedProminent) }
    }

    /// A transparent window toolbar (macOS 15 and later; macOS 14 keeps its default).
    @ViewBuilder
    func nexHiddenWindowToolbarBackground() -> some View {
        if #available(macOS 15, *) { toolbarBackgroundVisibility(.hidden, for: .windowToolbar) } else { self }
    }

    /// In full screen, the toolbar only slides in with the menu bar (macOS 15 and later).
    @ViewBuilder
    public func nexToolbarOnHoverInFullScreen() -> some View {
        if #available(macOS 15, *) { windowToolbarFullScreenVisibility(.onHover) } else { self }
    }
}

extension ToolbarContent {
    /// No shared glass capsule behind a toolbar item (macOS 26 draws one; earlier systems don't).
    @ToolbarContentBuilder
    func nexNoSharedBackground() -> some ToolbarContent {
        if #available(macOS 26, *) { sharedBackgroundVisibility(.hidden) } else { self }
    }
}

/// A flexible toolbar spacer on macOS 26 (it keeps the window controls inside the floating sidebar);
/// nothing before, where the sidebar isn't floating.
struct NexFlexibleToolbarSpacer: ToolbarContent {
    var body: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarSpacer(.flexible)
        } else {
            ToolbarItem(placement: .automatic) { EmptyView() }
        }
    }
}
