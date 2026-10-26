import Foundation

/// An sRGB colour with WCAG helpers. Foundation only, so the widget extension can compile it.
public struct HexColor: Equatable, Hashable, Sendable {
    public let red: Double, green: Double, blue: Double

    public init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).lowercased()
        let value = UInt32(clean, radix: 16) ?? 0
        red = Double((value >> 16) & 0xff) / 255
        green = Double((value >> 8) & 0xff) / 255
        blue = Double(value & 0xff) / 255
    }

    public var hexString: String {
        func byte(_ v: Double) -> Int { Int((v * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(red), byte(green), byte(blue))
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(red) + 0.7152 * lin(green) + 0.0722 * lin(blue)
    }

    public static func contrast(_ a: HexColor, _ b: HexColor) -> Double {
        let (hi, lo) = a.luminance >= b.luminance ? (a, b) : (b, a)
        return (hi.luminance + 0.05) / (lo.luminance + 0.05)
    }
}

public struct Palette: Equatable, Sendable {
    public let canvas, surface, fg, fg2, fg3, line: HexColor
    public let accent, accentHover, accentSoft: HexColor
    /// Text colour for content drawn on `accent`: white or ink, whichever contrasts more.
    public var onAccent: HexColor {
        let white = HexColor(hex: "#ffffff"), ink = HexColor(hex: "#0b0d12")
        return HexColor.contrast(white, accent) >= HexColor.contrast(ink, accent) ? white : ink
    }
}

/// Colours from nexventures.net's own stylesheet (neutrals + "ember" accent); the other themes swap only the accent family.
public enum ThemeCatalog {
    public static let displayNames: [ThemeID: String] = [
        .ember: "Nexventures Ember", .ocean: "Ocean", .forest: "Forest", .violet: "Violet", .graphite: "Graphite",
    ]

    private static func neutrals(dark: Bool) -> (canvas: String, surface: String, fg: String, fg2: String, fg3: String, line: String) {
        dark ? ("#07080c", "#0f1117", "#f3f4f7", "#aeb4c2", "#767d8f", "#2c3140")
             : ("#f7f8fa", "#ffffff", "#0b0d12", "#454c5a", "#697285", "#e2dfdb")
    }

    /// (accent, hover, soft)
    private static func accents(_ theme: ThemeID, dark: Bool) -> (String, String, String) {
        switch (theme, dark) {
        case (.ember, false): return ("#cf3f0e", "#a8320b", "#fff0e8")
        case (.ember, true): return ("#f0561f", "#ff7440", "#2a140c")
        case (.ocean, false): return ("#1d6fd6", "#1556ab", "#e8f1fd")
        case (.ocean, true): return ("#4c9aff", "#7ab4ff", "#0e1b2e")
        case (.forest, false): return ("#1f7a4d", "#16603c", "#e6f4ec")
        case (.forest, true): return ("#3ccf8e", "#6fe0ab", "#0c2218")
        case (.violet, false): return ("#7c3aed", "#6128c4", "#f1eafe")
        case (.violet, true): return ("#a78bfa", "#c4b0fd", "#1c1432")
        case (.graphite, false): return ("#3b4252", "#2a303c", "#eceef2")
        case (.graphite, true): return ("#c3c9d6", "#e1e5ee", "#1c1f27")
        }
    }

    public static func palette(_ theme: ThemeID, dark: Bool) -> Palette {
        let n = neutrals(dark: dark), a = accents(theme, dark: dark)
        return Palette(canvas: HexColor(hex: n.canvas), surface: HexColor(hex: n.surface), fg: HexColor(hex: n.fg),
                       fg2: HexColor(hex: n.fg2), fg3: HexColor(hex: n.fg3), line: HexColor(hex: n.line),
                       accent: HexColor(hex: a.0), accentHover: HexColor(hex: a.1), accentSoft: HexColor(hex: a.2))
    }
}
