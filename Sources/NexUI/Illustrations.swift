import SwiftUI
import NexCore

public enum IllustrationKind: CaseIterable, Sendable {
    case rocket, branchGraph, terminal, swatches, folders, telescope, widgets, power
}

/// Flat vector illustrations drawn in code. They scale to their container and use only theme colours,
/// so they follow the theme and light/dark automatically.
public struct IllustrationView: View {
    @Environment(\.theme) private var theme
    let kind: IllustrationKind

    public init(_ kind: IllustrationKind) { self.kind = kind }

    public var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 100
            var c = context
            c.translateBy(x: (size.width - 100 * unit) / 2, y: (size.height - 100 * unit) / 2)
            c.scaleBy(x: unit, y: unit)
            Painter(ctx: c, theme: theme).draw(kind)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Drawing happens in a 100 × 100 design space.
private struct Painter {
    let ctx: GraphicsContext
    let theme: Theme

    private var ink: Color { Color(red: 0.07, green: 0.08, blue: 0.11) }

    func draw(_ kind: IllustrationKind) {
        // Soft backdrop disc shared by all illustrations.
        fill(Path(ellipseIn: CGRect(x: 6, y: 8, width: 88, height: 88)), theme.accentSoft)
        switch kind {
        case .rocket: rocket()
        case .branchGraph: branchGraph()
        case .terminal: terminal()
        case .swatches: swatches()
        case .folders: folders()
        case .telescope: telescope()
        case .widgets: widgets()
        case .power: power()
        }
    }

    // MARK: helpers

    private func fill(_ path: Path, _ color: Color) { ctx.fill(path, with: .color(color)) }
    private func stroke(_ path: Path, _ color: Color, _ width: CGFloat) {
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
    private func rounded(_ rect: CGRect, _ r: CGFloat) -> Path { Path(roundedRect: rect, cornerRadius: r, style: .continuous) }
    private func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: Color) {
        fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), color)
    }
    private func sparkle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: Color) {
        var p = Path()
        p.move(to: CGPoint(x: x, y: y - r)); p.addQuadCurve(to: CGPoint(x: x + r, y: y), control: CGPoint(x: x, y: y))
        p.addQuadCurve(to: CGPoint(x: x, y: y + r), control: CGPoint(x: x, y: y)); p.addQuadCurve(to: CGPoint(x: x - r, y: y), control: CGPoint(x: x, y: y))
        p.addQuadCurve(to: CGPoint(x: x, y: y - r), control: CGPoint(x: x, y: y))
        fill(p, color)
    }

    // MARK: drawings

    private func rocket() {
        var c = ctx
        c.translateBy(x: 50, y: 52)
        c.rotate(by: .degrees(40))
        let p = Painter(ctx: c, theme: theme)
        // flame
        var flame = Path()
        flame.move(to: CGPoint(x: -7, y: 24)); flame.addQuadCurve(to: CGPoint(x: 0, y: 46), control: CGPoint(x: -9, y: 38))
        flame.addQuadCurve(to: CGPoint(x: 7, y: 24), control: CGPoint(x: 9, y: 38)); flame.closeSubpath()
        p.fill(flame, theme.accentHover)
        var inner = Path()
        inner.move(to: CGPoint(x: -3.5, y: 24)); inner.addQuadCurve(to: CGPoint(x: 0, y: 37), control: CGPoint(x: -4, y: 32))
        inner.addQuadCurve(to: CGPoint(x: 3.5, y: 24), control: CGPoint(x: 4, y: 32)); inner.closeSubpath()
        p.fill(inner, Color.yellow.opacity(0.9))
        // fins
        var fins = Path()
        fins.move(to: CGPoint(x: -11, y: 8)); fins.addLine(to: CGPoint(x: -22, y: 28)); fins.addLine(to: CGPoint(x: -8, y: 24)); fins.closeSubpath()
        fins.move(to: CGPoint(x: 11, y: 8)); fins.addLine(to: CGPoint(x: 22, y: 28)); fins.addLine(to: CGPoint(x: 8, y: 24)); fins.closeSubpath()
        p.fill(fins, theme.accent)
        // body
        var body = Path()
        body.move(to: CGPoint(x: 0, y: -34)); body.addQuadCurve(to: CGPoint(x: 12, y: -4), control: CGPoint(x: 13, y: -22))
        body.addLine(to: CGPoint(x: 11, y: 26)); body.addLine(to: CGPoint(x: -11, y: 26)); body.addLine(to: CGPoint(x: -12, y: -4))
        body.addQuadCurve(to: CGPoint(x: 0, y: -34), control: CGPoint(x: -13, y: -22)); body.closeSubpath()
        p.fill(body, theme.surface)
        p.stroke(body, theme.line, 1)
        var nose = Path()
        nose.move(to: CGPoint(x: 0, y: -34)); nose.addQuadCurve(to: CGPoint(x: 10, y: -14), control: CGPoint(x: 9, y: -26))
        nose.addLine(to: CGPoint(x: -10, y: -14)); nose.addQuadCurve(to: CGPoint(x: 0, y: -34), control: CGPoint(x: -9, y: -26)); nose.closeSubpath()
        p.fill(nose, theme.accent)
        p.dot(0, -2, 7, theme.fg); p.dot(0, -2, 4.6, theme.accent.opacity(0.55))
        p.fill(p.rounded(CGRect(x: -11, y: 16, width: 22, height: 4), 2), theme.accent)
        sparkle(20, 24, 5, theme.accent); sparkle(80, 34, 4, theme.fg3); dot(26, 74, 2, theme.fg3); dot(78, 76, 2.5, theme.accent.opacity(0.6))
    }

    private func branchGraph() {
        let main = Path { p in p.move(to: CGPoint(x: 38, y: 20)); p.addLine(to: CGPoint(x: 38, y: 82)) }
        stroke(main, theme.fg3, 4)
        let branch = Path { p in
            p.move(to: CGPoint(x: 38, y: 62)); p.addCurve(to: CGPoint(x: 66, y: 44), control1: CGPoint(x: 38, y: 50), control2: CGPoint(x: 66, y: 58))
            p.addLine(to: CGPoint(x: 66, y: 32)); p.addCurve(to: CGPoint(x: 38, y: 24), control1: CGPoint(x: 66, y: 22), control2: CGPoint(x: 38, y: 34))
        }
        stroke(branch, theme.accent, 4)
        for (x, y, accent) in [(38.0, 20.0, false), (38.0, 82.0, false), (66.0, 44.0, true), (66.0, 32.0, true), (38.0, 52.0, false)] {
            dot(x, y, 9, theme.surface); dot(x, y, 6, accent ? theme.accent : theme.fg)
        }
        sparkle(80, 76, 5, theme.accent); dot(20, 36, 2.5, theme.fg3)
    }

    private func terminal() {
        let win = CGRect(x: 14, y: 24, width: 72, height: 54)
        fill(rounded(win.offsetBy(dx: 0, dy: 3), 9), .black.opacity(0.12))
        fill(rounded(win, 9), ink)
        fill(rounded(CGRect(x: 14, y: 24, width: 72, height: 12), 9), Color.white.opacity(0.08))
        for (i, color) in [Color.red.opacity(0.85), Color.yellow.opacity(0.85), Color.green.opacity(0.85)].enumerated() { dot(23 + CGFloat(i) * 7, 30, 2.2, color) }
        let prompt = Path { p in p.move(to: CGPoint(x: 22, y: 45)); p.addLine(to: CGPoint(x: 29, y: 50)); p.addLine(to: CGPoint(x: 22, y: 55)) }
        stroke(prompt, theme.accent, 3)
        fill(rounded(CGRect(x: 34, y: 48, width: 26, height: 4), 2), .white.opacity(0.55))
        fill(rounded(CGRect(x: 22, y: 60, width: 38, height: 4), 2), .white.opacity(0.25))
        fill(rounded(CGRect(x: 22, y: 68, width: 22, height: 4), 2), .white.opacity(0.25))
        fill(rounded(CGRect(x: 48, y: 66, width: 6, height: 8), 1.5), theme.accent)
        sparkle(82, 20, 5, theme.accent); dot(16, 84, 2.5, theme.fg3)
    }

    private func swatches() {
        for (x, y, color, opacity) in [(38.0, 40.0, theme.accent, 1.0), (62.0, 40.0, theme.accentHover, 0.9),
                                       (38.0, 62.0, theme.fg3, 0.85), (62.0, 62.0, theme.surface, 1.0)] {
            dot(x, y, 20, color.opacity(opacity))
        }
        stroke(Path(ellipseIn: CGRect(x: 42, y: 42, width: 40, height: 40)), theme.line, 1.5)
        let brush = Path { p in p.move(to: CGPoint(x: 70, y: 22)); p.addLine(to: CGPoint(x: 84, y: 8)) }
        stroke(brush, theme.fg, 4); dot(69, 23, 4, theme.accent)
        sparkle(18, 20, 5, theme.accent); sparkle(82, 82, 4, theme.fg3)
    }

    private func folders() {
        func folder(_ x: CGFloat, _ y: CGFloat, _ color: Color, _ tab: Color) {
            fill(rounded(CGRect(x: x, y: y, width: 26, height: 12), 5), tab)
            fill(rounded(CGRect(x: x, y: y + 6, width: 56, height: 36), 7), color)
        }
        folder(16, 22, theme.accent.opacity(0.55), theme.accent.opacity(0.55))
        folder(24, 34, theme.accentHover.opacity(0.75), theme.accentHover.opacity(0.75))
        folder(30, 46, theme.surface, theme.surface)
        stroke(rounded(CGRect(x: 30, y: 52, width: 56, height: 36), 7), theme.line, 1.2)
        fill(rounded(CGRect(x: 38, y: 66, width: 26, height: 4), 2), theme.fg3.opacity(0.6))
        fill(rounded(CGRect(x: 38, y: 74, width: 16, height: 4), 2), theme.fg3.opacity(0.4))
        sparkle(80, 24, 5, theme.accent)
    }

    private func telescope() {
        let legs = Path { p in
            p.move(to: CGPoint(x: 50, y: 54)); p.addLine(to: CGPoint(x: 34, y: 88))
            p.move(to: CGPoint(x: 50, y: 54)); p.addLine(to: CGPoint(x: 66, y: 88))
            p.move(to: CGPoint(x: 50, y: 54)); p.addLine(to: CGPoint(x: 50, y: 88))
        }
        stroke(legs, theme.fg3, 3.5)
        var c = ctx
        c.translateBy(x: 50, y: 48); c.rotate(by: .degrees(-28))
        let p = Painter(ctx: c, theme: theme)
        p.fill(p.rounded(CGRect(x: -30, y: -7, width: 22, height: 14), 4), theme.accent)
        p.fill(p.rounded(CGRect(x: -10, y: -9, width: 24, height: 18), 4), theme.surface)
        p.stroke(p.rounded(CGRect(x: -10, y: -9, width: 24, height: 18), 4), theme.line, 1)
        p.fill(p.rounded(CGRect(x: 12, y: -12, width: 22, height: 24), 5), theme.accentHover)
        p.fill(p.rounded(CGRect(x: 34, y: -9, width: 4, height: 18), 2), theme.fg)
        sparkle(22, 22, 6, theme.accent); sparkle(80, 70, 4, theme.fg3); dot(18, 60, 2, theme.fg3); dot(76, 20, 2.5, theme.accent.opacity(0.6))
    }

    private func widgets() {
        fill(rounded(CGRect(x: 16, y: 20, width: 36, height: 36), 10), theme.surface)
        stroke(rounded(CGRect(x: 16, y: 20, width: 36, height: 36), 10), theme.line, 1.2)
        stroke(Path(ellipseIn: CGRect(x: 24, y: 28, width: 20, height: 20)), theme.accentSoft, 5)
        stroke(Path { p in p.addArc(center: CGPoint(x: 34, y: 38), radius: 10, startAngle: .degrees(-90), endAngle: .degrees(130), clockwise: false) }, theme.accent, 5)
        fill(rounded(CGRect(x: 56, y: 20, width: 28, height: 70), 10), theme.surface)
        stroke(rounded(CGRect(x: 56, y: 20, width: 28, height: 70), 10), theme.line, 1.2)
        for (i, h) in [30.0, 18.0, 40.0].enumerated() { fill(rounded(CGRect(x: 61 + CGFloat(i) * 7.5, y: 80 - h, width: 5, height: h), 2.5), i == 2 ? theme.accent : theme.accentHover.opacity(0.6)) }
        fill(rounded(CGRect(x: 16, y: 62, width: 36, height: 28), 10), theme.accent)
        fill(rounded(CGRect(x: 22, y: 70, width: 18, height: 4), 2), theme.onAccent.opacity(0.9))
        fill(rounded(CGRect(x: 22, y: 78, width: 24, height: 4), 2), theme.onAccent.opacity(0.55))
        sparkle(84, 16, 4, theme.accent)
    }

    private func power() {
        // sunrise
        for i in 0..<7 {
            let a = Angle.degrees(200 + Double(i) * 23.3).radians
            let from = CGPoint(x: 50 + cos(a) * 30, y: 74 + sin(a) * 30), to = CGPoint(x: 50 + cos(a) * 38, y: 74 + sin(a) * 38)
            stroke(Path { p in p.move(to: from); p.addLine(to: to) }, theme.accent.opacity(0.6), 2.5)
        }
        fill(Path { p in p.addArc(center: CGPoint(x: 50, y: 74), radius: 24, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false); p.closeSubpath() }, theme.accent)
        fill(rounded(CGRect(x: 12, y: 74, width: 76, height: 5), 2.5), theme.fg3.opacity(0.6))
        // power button
        dot(50, 38, 20, theme.surface); stroke(Path(ellipseIn: CGRect(x: 30, y: 18, width: 40, height: 40)), theme.line, 1.2)
        stroke(Path { p in p.addArc(center: CGPoint(x: 50, y: 38), radius: 9, startAngle: .degrees(-60), endAngle: .degrees(240), clockwise: false) }, theme.accent, 4)
        stroke(Path { p in p.move(to: CGPoint(x: 50, y: 25)); p.addLine(to: CGPoint(x: 50, y: 37)) }, theme.accent, 4)
        sparkle(18, 28, 4, theme.accent); sparkle(84, 44, 3.5, theme.fg3)
    }
}
