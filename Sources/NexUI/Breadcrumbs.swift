import SwiftUI
import NexCore
import NexApp

/// "Projects › sessions › week1" in a glass capsule; every crumb but the last navigates.
struct BreadcrumbBar: View {
    @Environment(\.theme) private var theme
    let crumbs: [Crumb]
    let onSelect: (AppPage) -> Void

    /// Long trails keep the first crumb and the last two, with "…" for the rest.
    private var visible: [Crumb?] {
        guard crumbs.count > 4 else { return crumbs }
        return [crumbs[0], nil] + crumbs.suffix(2)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(visible.enumerated()), id: \.offset) { index, crumb in
                if index > 0 {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(theme.fg3)
                }
                if let crumb {
                    item(crumb, first: index == 0)
                } else {
                    hiddenCrumbs
                }
            }
        }
        .padding(.horizontal, 12).frame(height: 34)
        .fixedSize()                            // the toolbar would otherwise squeeze it to "Proje…"
        .nexGlass(in: Capsule())
        .animation(.spring(duration: 0.3), value: crumbs.map(\.title))
    }

    @ViewBuilder private func item(_ crumb: Crumb, first: Bool) -> some View {
        if let page = crumb.page {
            Button { onSelect(page) } label: {
                HStack(spacing: 4) {
                    if first { Image(systemName: "square.grid.2x2").font(.system(size: 10, weight: .semibold)) }
                    Text(crumb.title).lineLimit(1).fixedSize()
                }
                .font(.callout.weight(.medium)).foregroundStyle(theme.fg2)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .contentShape(Capsule())
            }
            .buttonStyle(CrumbButtonStyle())
            .help("Go to \(crumb.title)")
        } else {
            Text(crumb.title).font(.callout.weight(.semibold)).foregroundStyle(theme.fg).lineLimit(1)
                .padding(.horizontal, 6)
        }
    }

    private var hiddenCrumbs: some View {
        let middle = Array(crumbs.dropFirst().dropLast(2))
        return Menu {
            ForEach(Array(middle.enumerated()), id: \.offset) { _, crumb in
                if let page = crumb.page { Button(crumb.title) { onSelect(page) } }
            }
        } label: { Text("…").font(.callout.weight(.semibold)).foregroundStyle(theme.fg2) }
        .menuStyle(.button).buttonStyle(.plain).fixedSize()
    }
}

private struct CrumbButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Capsule().fill(theme.accentSoft.opacity(hovering ? 1 : 0)))
            .foregroundStyle(hovering ? theme.accent : theme.fg2)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
