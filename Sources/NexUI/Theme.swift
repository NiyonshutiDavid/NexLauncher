import SwiftUI
import NexCore

/// Resolved colours for the active theme and light/dark mode. Views read this from the environment
/// and never hard-code colours.
public struct Theme: Sendable {
    public let id: ThemeID
    public let dark: Bool
    public let palette: Palette

    public static func resolve(_ id: ThemeID, dark: Bool) -> Theme {
        Theme(id: id, dark: dark, palette: ThemeCatalog.palette(id, dark: dark))
    }

    private func color(_ c: HexColor) -> Color { Color(red: c.red, green: c.green, blue: c.blue) }
    public var canvas: Color { color(palette.canvas) }
    public var surface: Color { color(palette.surface) }
    public var fg: Color { color(palette.fg) }
    public var fg2: Color { color(palette.fg2) }
    public var fg3: Color { color(palette.fg3) }
    public var line: Color { color(palette.line) }
    public var accent: Color { color(palette.accent) }
    public var accentHover: Color { color(palette.accentHover) }
    public var accentSoft: Color { color(palette.accentSoft) }
    public var onAccent: Color { color(palette.onAccent) }
}

extension EnvironmentValues {
    @Entry public var theme: Theme = .resolve(.ember, dark: false)
}

private struct ThemeResolver: ViewModifier {
    let id: ThemeID
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let theme = Theme.resolve(id, dark: scheme == .dark)
        content.environment(\.theme, theme).tint(theme.accent)       // tint follows the resolved (not requested) appearance
    }
}

private struct ThemeRoot: ViewModifier {
    let id: ThemeID
    let appearance: AppearanceMode
    func body(content: Content) -> some View {
        content
            .modifier(ThemeResolver(id: id))
            .preferredColorScheme(appearance == .light ? .light : appearance == .dark ? .dark : nil)
    }
}

extension View {
    /// Applies the chosen theme and appearance to this view tree.
    public func nexTheme(_ id: ThemeID, appearance: AppearanceMode) -> some View {
        modifier(ThemeRoot(id: id, appearance: appearance))
    }
}
