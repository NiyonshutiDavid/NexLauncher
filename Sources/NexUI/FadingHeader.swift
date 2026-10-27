import SwiftUI
import NexCore

/// WhatsApp-style header: no bar. Floating glass buttons and a centred title (in the transparent window toolbar)
/// over a soft fade, so the content dissolves beneath it.
enum HeaderMetrics {
    /// The header row sits level with the window controls, from the very top of the window.
    static let height: CGFloat = 54
    /// Scroll content starts below the header but scrolls up under the fade.
    static let contentInset: CGFloat = 8
}

extension View {
    func fadingHeader<Leading: View, Trailing: View>(
        title: String,
        @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        modifier(FadingHeaderModifier(center: HeaderTitle(title: title), leading: leading(), trailing: trailing()))
    }

    /// The same header with a clickable breadcrumb in the middle instead of a title.
    func fadingHeader<Leading: View, Trailing: View>(
        crumbs: [Crumb],
        onSelect: @escaping (AppPage) -> Void,
        @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        modifier(FadingHeaderModifier(center: BreadcrumbBar(crumbs: crumbs, onSelect: onSelect), leading: leading(), trailing: trailing()))
    }
}

private struct HeaderTitle: View {
    @Environment(\.theme) private var theme
    let title: String
    var body: some View {
        Text(title).font(.headline.weight(.semibold)).foregroundStyle(theme.fg).lineLimit(1).frame(maxWidth: 360)
    }
}

private struct FadingHeaderModifier<Center: View, Leading: View, Trailing: View>: ViewModifier {
    @Environment(\.theme) private var theme
    let center: Center
    let leading: Leading
    let trailing: Trailing

    func body(content: Content) -> some View {
        content
            .contentMargins(.top, HeaderMetrics.contentInset, for: .scrollContent)
            .overlay(alignment: .top) {
                // The fade: opaque canvas at the very top, gone by the bottom of the header.
                LinearGradient(stops: [.init(color: theme.canvas, location: 0),
                                       .init(color: theme.canvas.opacity(0.85), location: 0.45),
                                       .init(color: theme.canvas.opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: HeaderMetrics.height + 34)
                    .allowsHitTesting(false)
                    .ignoresSafeArea(.container, edges: .top)     // start at the window's top edge, no strip above
            }
            // The controls live in the window's (transparent) toolbar: it sits over this strip and would
            // otherwise take every click meant for buttons drawn underneath it.
            .toolbar {
                ToolbarItemGroup(placement: .navigation) { leading }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .principal) { center }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItemGroup(placement: .primaryAction) { trailing }
                    .sharedBackgroundVisibility(.hidden)
            }
    }
}

/// A round glass button for the header (like WhatsApp's "…").
struct HeaderCircleButton: View {
    @Environment(\.theme) private var theme
    let symbol: String
    let help: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) { HeaderCircleLabel(symbol: symbol, prominent: prominent) }
            .buttonStyle(PressableStyle())
            .help(help)
    }
}

struct HeaderCircleLabel: View {
    @Environment(\.theme) private var theme
    let symbol: String
    var prominent = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: prominent ? 16 : 14, weight: prominent ? .bold : .semibold))
            .foregroundStyle(prominent ? theme.onAccent : theme.fg)
            .frame(width: 38, height: 38)
            .background { if prominent { Circle().fill(theme.accent) } }
            .glassEffect(prominent ? .regular.tint(theme.accent) : .regular, in: Circle())
            .contentShape(Circle())
    }
}

/// The back button used on detail pages.
struct HeaderBackButton: View {
    let action: () -> Void
    var body: some View { HeaderCircleButton(symbol: "chevron.left", help: "Back to projects", action: action) }
}

/// A glass search capsule for the header.
struct HeaderSearchField: View {
    @Environment(\.theme) private var theme
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.fg2)
            TextField("Search projects", text: $text).textFieldStyle(.plain).frame(width: 180)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(theme.fg3)
            }
        }
        .padding(.horizontal, 14).frame(height: 38)
        .glassEffect(.regular, in: Capsule())
    }
}

/// Cards ⇄ Folders as two round glass buttons in one capsule.
struct HeaderViewModeToggle: View {
    @Environment(\.theme) private var theme
    @Binding var mode: ViewMode

    var body: some View {
        HStack(spacing: 2) {
            segment(.cards, "square.grid.2x2", "Cards")
            segment(.folders, "list.bullet.indent", "Folders")
        }
        .padding(3)
        .glassEffect(.regular, in: Capsule())
    }

    private func segment(_ value: ViewMode, _ symbol: String, _ help: String) -> some View {
        Button { withAnimation(.spring(duration: 0.3)) { mode = value } } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(mode == value ? theme.accent : theme.fg2)
                .frame(width: 34, height: 32)
                .background { if mode == value { Capsule().fill(theme.accentSoft) } }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain).help(help)
    }
}
