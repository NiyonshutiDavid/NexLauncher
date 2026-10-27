import Foundation
import Adwaita
import NexApp
import NexCore

/// Type, framework, collections, git and status filters (the Mac filter popover's options).
struct FilterPanel: View {
    let model: AppModel

    private func flag<T: Hashable>(_ set: WritableKeyPath<ProjectFilterSet, Set<T>>, _ value: T) -> Binding<Bool> {
        Binding(get: { model.filters[keyPath: set].contains(value) },
                set: { on in if on { model.filters[keyPath: set].insert(value) } else { model.filters[keyPath: set].remove(value) } })
    }

    var view: Body {
        ScrollView {
            VStack(spacing: 12) {
                Form {
                    ForEach(KindFilter.allCases) { kind in
                        SwitchRow(kind.rawValue, isOn: flag(\.kinds, kind))
                    }
                }
                Form {
                    ComboRow("Collections", selection: Binding(get: { model.filters.collections.rawValue },
                                                                set: { raw in if let mode = CollectionMode(rawValue: raw) { model.filters.collections = mode } }),
                             values: CollectionMode.allCases.map { ChoiceItem(id: $0.rawValue) })
                    ComboRow("Git", selection: Binding(get: { model.filters.git.rawValue },
                                                        set: { raw in if let git = GitFilter(rawValue: raw) { model.filters.git = git } }),
                             values: GitFilter.allCases.map { ChoiceItem(id: $0.rawValue) })
                    SwitchRow("Running only", isOn: Binding(get: { model.filters.onlyRunning }, set: { model.filters.onlyRunning = $0 }))
                    SwitchRow("Pinned only", isOn: Binding(get: { model.filters.onlyPinned }, set: { model.filters.onlyPinned = $0 }))
                }
                if !model.availableFrameworks.isEmpty {
                    Form {
                        ForEach(model.availableFrameworks.map { ChoiceItem(id: $0) }) { fw in
                            SwitchRow(fw.id, isOn: flag(\.frameworks, fw.id))
                        }
                    }
                }
                Button("Clear all") { model.clearFilters() }.flat().halign(.end)
            }
            .padding(12)
        }
        .frame(minWidth: 320, minHeight: 420)
    }
}

/// The active filters as removable chips above the grid.
struct FilterChips: View {
    let model: AppModel
    var view: Body {
        HStack(spacing: 6) {
            Text("Filtered").style("dim-label")
            Button("Clear all") { model.clearFilters() }.flat()
        }
        .halign(.start)
    }
}

/// A plain string choice for combo rows.
struct ChoiceItem: Identifiable, CustomStringConvertible {
    let id: String
    var description: String { id }
}
