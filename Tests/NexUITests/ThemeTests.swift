import Testing
import Foundation
import NexCore
@testable import NexUI

private func target(_ kind: ServiceKind, _ fw: String?) -> ServiceTarget {
    ServiceTarget(kind: kind, directory: URL(fileURLWithPath: "/tmp"), framework: fw, command: "")
}
private func project(_ t: [ServiceTarget]) -> Project { Project(id: "x", name: "X", root: URL(fileURLWithPath: "/tmp"), targets: t) }

@Suite struct ThemeTests {
    @Test func hueIsStableAndInUnitRange() {
        #expect(IconStyle.hue(for: "CleanPay") == IconStyle.hue(for: "CleanPay"))
        #expect(IconStyle.hue(for: "CleanPay") != IconStyle.hue(for: "Jarama"))
        for n in ["", "a", "Kigali Height Proposal", "é✓"] { #expect((0...1).contains(IconStyle.hue(for: n))) }
    }

    @Test func subtitleFullStackNamesFrameworks() {
        #expect(ProjectSubtitle.text(for: project([target(.frontend, "Vite"), target(.backend, "Django")])) == "Full-stack · Vite + Django")
    }
    @Test func subtitleFullStackWithoutFrameworks() {
        #expect(ProjectSubtitle.text(for: project([target(.frontend, nil), target(.backend, nil)])) == "Full-stack")
    }
    @Test func subtitleFrontendOnly() { #expect(ProjectSubtitle.text(for: project([target(.frontend, "Vite")])) == "Frontend · Vite") }
    @Test func subtitleFlutterOnly() { #expect(ProjectSubtitle.text(for: project([target(.flutter, "Flutter")])) == "Flutter") }
    @Test func subtitleDockerOnly() { #expect(ProjectSubtitle.text(for: project([target(.docker, "Docker")])) == "Docker") }
    @Test func subtitleFrontendPlusFlutter() {
        #expect(ProjectSubtitle.text(for: project([target(.frontend, "Vite"), target(.flutter, "Flutter")])) == "Frontend + Flutter")
    }

    @Test func glyphPerKind() {
        #expect(ProjectGlyph.symbol(for: project([target(.frontend, nil), target(.backend, nil)])) == "rectangle.on.rectangle")
        #expect(ProjectGlyph.symbol(for: project([target(.backend, nil)])) == "server.rack")
        #expect(ProjectGlyph.symbol(for: project([target(.flutter, nil)])) == "iphone")
        #expect(ProjectGlyph.symbol(for: project([target(.docker, nil)])) == "shippingbox")
        #expect(ProjectGlyph.symbol(for: project([target(.frontend, nil)])) == "macwindow")
    }

    @Test func themeResolvesDarkPaletteWhenDark() {
        #expect(Theme.resolve(.ember, dark: true).palette == ThemeCatalog.palette(.ember, dark: true))
        #expect(Theme.resolve(.ocean, dark: false).palette == ThemeCatalog.palette(.ocean, dark: false))
    }
}
