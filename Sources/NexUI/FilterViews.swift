import SwiftUI
import NexCore
import NexApp

/// A round header button that opens the filter panel; shows how many filters are on.
struct HeaderFilterButton: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            HeaderCircleLabel(symbol: "line.3.horizontal.decrease")
                .overlay(alignment: .topTrailing) {
                    if model.filters.activeCount > 0 {
                        Text("\(model.filters.activeCount)").font(.caption2.weight(.bold)).foregroundStyle(theme.onAccent)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Circle().fill(theme.accent))
                            .offset(x: 3, y: -3)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.3), value: model.filters.activeCount)
        }
        .buttonStyle(PressableStyle())
        .help("Filter projects")
        .popover(isPresented: $open, arrowEdge: .bottom) { FilterPanel(model: model) }
    }
}

/// Type, framework, collections, git and status filters.
struct FilterPanel: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Filter projects").font(.headline).foregroundStyle(theme.fg)
                Spacer()
                if model.filters.isActive {
                    Button("Clear all") { withAnimation { model.clearFilters() } }
                        .buttonStyle(.plain).font(.callout.weight(.semibold)).foregroundStyle(theme.accent)
                }
            }

            section("Type") {
                FlowLayout(spacing: 6) {
                    ForEach(KindFilter.allCases) { kind in
                        FilterChip(title: kind.rawValue, selected: model.filters.kinds.contains(kind)) {
                            model.filters.kinds.formSymmetricDifference([kind])
                        }
                    }
                }
            }

            if !model.availableFrameworks.isEmpty {
                section("Framework") {
                    ScrollView {
                        FlowLayout(spacing: 6) {
                            ForEach(model.availableFrameworks, id: \.self) { name in
                                FilterChip(title: name, selected: model.filters.frameworks.contains(name)) {
                                    model.filters.frameworks.formSymmetricDifference([name])
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 96)
                }
            }

            section("Collections") {
                Picker("", selection: $model.filters.collections) {
                    ForEach(CollectionMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                Text(collectionsHelp).font(.caption).foregroundStyle(theme.fg3)
            }

            section("Git") {
                Picker("", selection: $model.filters.git) {
                    ForEach(GitFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }

            HStack(spacing: 18) {
                Toggle("Running only", isOn: $model.filters.onlyRunning)
                Toggle("Pinned only", isOn: $model.filters.onlyPinned)
            }
            .toggleStyle(.checkbox)
        }
        .padding(18)
        .frame(width: 420)
        .animation(.easeInOut(duration: 0.2), value: model.filters)
    }

    private var collectionsHelp: String {
        switch model.filters.collections {
        case .show: return "Collections appear as cards you can open."
        case .expand: return "The apps inside collections are listed alongside the others."
        case .hide: return "Collections and the apps inside them are left out."
        case .only: return "Only collections are shown."
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(theme.fg3)
            content()
        }
    }
}

/// The active filters as removable chips above the grid.
struct ActiveFilterBar: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(KindFilter.allCases.filter { model.filters.kinds.contains($0) }) { kind in
                chip(kind.rawValue) { model.filters.kinds.remove(kind) }
            }
            ForEach(model.filters.frameworks.sorted(), id: \.self) { name in
                chip(name) { model.filters.frameworks.remove(name) }
            }
            if model.filters.collections != .show {
                chip("Collections: \(model.filters.collections.rawValue)") { model.filters.collections = .show }
            }
            if model.filters.git != .any { chip(model.filters.git.rawValue) { model.filters.git = .any } }
            if model.filters.onlyRunning { chip("Running") { model.filters.onlyRunning = false } }
            if model.filters.onlyPinned { chip("Pinned") { model.filters.onlyPinned = false } }
            Button("Clear all") { withAnimation { model.clearFilters() } }
                .buttonStyle(.plain).font(.callout.weight(.semibold)).foregroundStyle(theme.accent)
                .padding(.vertical, 6)
        }
        .animation(.spring(duration: 0.3), value: model.filters)
    }

    private func chip(_ title: String, remove: @escaping () -> Void) -> some View {
        Button { withAnimation { remove() } } label: {
            HStack(spacing: 6) {
                Text(title)
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .font(.callout.weight(.medium)).foregroundStyle(theme.accent)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(theme.accentSoft))
        }
        .buttonStyle(PressableStyle())
        .help("Remove this filter")
        .transition(.scale.combined(with: .opacity))
    }
}

struct FilterChip: View {
    @Environment(\.theme) private var theme
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if selected { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                Text(title)
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(selected ? theme.onAccent : theme.fg)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(Capsule().fill(selected ? theme.accent : theme.canvas))
            .overlay(Capsule().strokeBorder(selected ? Color.clear : theme.line))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .animation(.spring(duration: 0.25), value: selected)
    }
}

/// Lays children out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].items.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width && !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.items.isEmpty }
    }
}
