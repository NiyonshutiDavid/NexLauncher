import Testing
import Foundation
@testable import NexCore

@Suite struct ThemePaletteTests {
    @Test func emberMatchesNexventuresTokensExactly() {
        let l = ThemeCatalog.palette(.ember, dark: false)
        #expect(l.canvas.hexString == "#f7f8fa"); #expect(l.surface.hexString == "#ffffff")
        #expect(l.fg.hexString == "#0b0d12"); #expect(l.fg2.hexString == "#454c5a"); #expect(l.fg3.hexString == "#697285")
        #expect(l.line.hexString == "#e2dfdb")
        #expect(l.accent.hexString == "#cf3f0e"); #expect(l.accentHover.hexString == "#a8320b"); #expect(l.accentSoft.hexString == "#fff0e8")
        let d = ThemeCatalog.palette(.ember, dark: true)
        #expect(d.canvas.hexString == "#07080c"); #expect(d.surface.hexString == "#0f1117")
        #expect(d.fg.hexString == "#f3f4f7"); #expect(d.fg2.hexString == "#aeb4c2"); #expect(d.fg3.hexString == "#767d8f")
        #expect(d.line.hexString == "#2c3140")
        #expect(d.accent.hexString == "#f0561f"); #expect(d.accentHover.hexString == "#ff7440"); #expect(d.accentSoft.hexString == "#2a140c")
    }

    @Test func contrastOfBlackOnWhiteIs21() {
        #expect(abs(HexColor.contrast(HexColor(hex: "#000000"), HexColor(hex: "#ffffff")) - 21) < 0.01)
    }

    @Test(arguments: ThemeID.allCases, [false, true])
    func everyThemeAndModeMeetsContrast(theme: ThemeID, dark: Bool) {
        let p = ThemeCatalog.palette(theme, dark: dark)
        #expect(HexColor.contrast(p.fg, p.surface) >= 4.5)
        #expect(HexColor.contrast(p.fg, p.canvas) >= 4.5)
        #expect(HexColor.contrast(p.fg2, p.surface) >= 4.5)
        #expect(HexColor.contrast(p.fg3, p.surface) >= 3)
        #expect(HexColor.contrast(p.onAccent, p.accent) >= 4.5)
        #expect(HexColor.contrast(p.accent, p.surface) >= 3, "accent must be visible on cards")
    }

    @Test(arguments: [false, true])
    func themesChangeOnlyAccentFamily(dark: Bool) {
        let base = ThemeCatalog.palette(.ember, dark: dark)
        for t in ThemeID.allCases {
            let p = ThemeCatalog.palette(t, dark: dark)
            #expect(p.canvas == base.canvas && p.surface == base.surface && p.fg == base.fg)
            #expect(p.fg2 == base.fg2 && p.fg3 == base.fg3 && p.line == base.line)
        }
    }

    @Test func hexParsingAcceptsHashAndCase() {
        #expect(HexColor(hex: "#CF3F0E") == HexColor(hex: "cf3f0e"))
        #expect(HexColor(hex: "cf3f0e").hexString == "#cf3f0e")
    }

    @Test func everyThemeHasADisplayName() {
        for t in ThemeID.allCases { #expect(ThemeCatalog.displayNames[t]?.isEmpty == false) }
    }
}
