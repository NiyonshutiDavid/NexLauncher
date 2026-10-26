import SwiftUI

/// A floating glass bar: real Liquid Glass tinted with the accent, a light-catching edge, a soft glow and
/// a lifted shadow. Content scrolls underneath it, so the glass actually has something to refract.
struct GlassBar<Content: View>: View {
    @Environment(\.theme) private var theme
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 24, style: .continuous) }

    var body: some View {
        HStack(spacing: 12) { content }
            .padding(.horizontal, 18).padding(.vertical, 10)
            .frame(minHeight: 56)
            .background {
                shape
                    .fill(.ultraThinMaterial)                                    // frosted base
                    .overlay(                                                    // accent tint and inner glow
                        LinearGradient(colors: [theme.accent.opacity(theme.dark ? 0.20 : 0.12), .clear, theme.accent.opacity(theme.dark ? 0.12 : 0.06)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: shape)
                    .overlay(alignment: .top) {                                  // soft top highlight
                        LinearGradient(colors: [.white.opacity(theme.dark ? 0.16 : 0.55), .clear], startPoint: .top, endPoint: .center)
                            .clipShape(shape)
                    }
            }
            .glassEffect(.regular.tint(theme.accent.opacity(0.10)), in: shape)   // lens/refraction from macOS 26
            .overlay {                                                           // light-catching rim
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(theme.dark ? 0.45 : 0.95), .white.opacity(0.06), .white.opacity(theme.dark ? 0.2 : 0.6)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
            .shadow(color: theme.accent.opacity(theme.dark ? 0.18 : 0.10), radius: 22, y: 8)
            .shadow(color: .black.opacity(theme.dark ? 0.45 : 0.10), radius: 12, y: 4)
    }
}

/// Space the glass bar occupies at the top of a page; scroll views add it as a content margin.
enum GlassHeaderMetrics { static let inset: CGFloat = 92 }

extension View {
    /// Overlays a floating glass header (title, optional leading and trailing controls) at the top of a page.
    func glassHeader<Leading: View, Trailing: View>(
        title: String,
        @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        modifier(GlassHeaderModifier(title: title, leading: leading(), trailing: trailing()))
    }
}

private struct GlassHeaderModifier<Leading: View, Trailing: View>: ViewModifier {
    @Environment(\.theme) private var theme
    let title: String
    let leading: Leading
    let trailing: Trailing

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            GlassBar {
                leading
                Text(title).font(.headline.weight(.semibold)).foregroundStyle(theme.fg).lineLimit(1)
                Spacer(minLength: 12)
                trailing
            }
            .padding(.horizontal, 24).padding(.top, 12)
        }
    }
}

/// Search field styled for the glass bar.
struct GlassSearchField: View {
    @Environment(\.theme) private var theme
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.fg3)
            TextField("Search projects", text: $text).textFieldStyle(.plain).frame(width: 190)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(theme.fg3)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(theme.surface.opacity(theme.dark ? 0.5 : 0.6), in: Capsule())
        .overlay(Capsule().strokeBorder(theme.line.opacity(0.8)))
    }
}
