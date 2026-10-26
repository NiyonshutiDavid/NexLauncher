import SwiftUI
import NexCore

public enum IconStyle {
    /// A stable hue in 0...1 derived from the name (FNV-1a), so every project keeps its colour.
    public static func hue(for name: String) -> Double {
        var hash: UInt32 = 2166136261
        for byte in name.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
        return Double(hash) / Double(UInt32.max)
    }
}

public enum ProjectSubtitle {
    public static func text(for project: Project) -> String {
        let kinds = ServiceKind.allCases.filter { k in project.targets.contains { $0.kind == k } }
        func fw(_ kind: ServiceKind) -> String? { project.targets.first { $0.kind == kind }?.framework }
        if project.isFullStack {
            let names = [fw(.frontend), fw(.backend)].compactMap { $0 }
            return names.isEmpty ? "Full-stack" : "Full-stack · " + names.joined(separator: " + ")
        }
        let titles = kinds.map { $0.rawValue.capitalized }.joined(separator: " + ")
        if kinds.count == 1, let name = fw(kinds[0]), name != titles { return "\(titles) · \(name)" }
        return titles
    }
}

public enum ProjectGlyph {
    public static func symbol(for project: Project) -> String {
        if project.isFullStack { return "rectangle.on.rectangle" }
        let kinds = Set(project.targets.map(\.kind))
        if kinds.contains(.frontend) { return "macwindow" }
        if kinds.contains(.backend) { return "server.rack" }
        if kinds.contains(.flutter) { return "iphone" }
        if kinds.contains(.docker) { return "shippingbox" }
        return "folder.fill"
    }
}

/// App-icon style tile: a squircle with a gradient seeded by the name and tinted by the theme accent.
public struct IconTile: View {
    @Environment(\.theme) private var theme
    let name: String
    let glyph: String
    var size: CGFloat = 56

    public init(name: String, glyph: String, size: CGFloat = 56) {
        self.name = name
        self.glyph = glyph
        self.size = size
    }

    public var body: some View {
        let hue = IconStyle.hue(for: name)
        let top = Color(hue: hue, saturation: theme.dark ? 0.55 : 0.60, brightness: theme.dark ? 0.78 : 0.95)
        let bottom = Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.75, brightness: theme.dark ? 0.55 : 0.78)
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Image(systemName: glyph).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white))
            .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .frame(width: size, height: size)
    }
}

public enum PillStyle { case prominent, quiet, destructive }

/// App Store-style capsule button ("GET" / "OPEN").
public struct Pill: View {
    @Environment(\.theme) private var theme
    let title: String
    var style: PillStyle = .prominent
    var systemImage: String? = nil
    let action: () -> Void

    public init(_ title: String, style: PillStyle = .prominent, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage).font(.caption.weight(.bold)) }
                Text(title.uppercased()).font(.system(size: 12, weight: .bold)).tracking(0.4)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch style {
        case .prominent: return theme.onAccent
        case .quiet: return theme.accent
        case .destructive: return .white
        }
    }
    private var background: Color {
        switch style {
        case .prominent: return theme.accent
        case .quiet: return theme.accentSoft
        case .destructive: return Color(red: 0.78, green: 0.2, blue: 0.18)
        }
    }
}

/// Solid card: radius 22, soft shadow in light mode, hairline in dark mode.
public struct CardSurface<Content: View>: View {
    @Environment(\.theme) private var theme
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        content
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                if theme.dark { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(theme.line, lineWidth: 1) }
            }
            .shadow(color: .black.opacity(theme.dark ? 0 : 0.06), radius: 12, y: 4)
    }
}

public struct SectionHeader: View {
    @Environment(\.theme) private var theme
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    public init(_ title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title2.weight(.bold)).foregroundStyle(theme.fg)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.plain).foregroundStyle(theme.accent).font(.callout.weight(.medium))
            }
        }
    }
}
