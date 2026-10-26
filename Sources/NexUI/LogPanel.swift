import SwiftUI
import NexCore
import NexProcess

struct LogPanel: View {
    @Bindable var model: AppModel
    let project: Project
    @State private var selected: ServiceKind?

    private var kinds: [ServiceKind] {
        let ids = model.processes.logs.keys.filter { $0.projectID == project.id }
        return ids.map(\.kind).sorted { $0.rawValue < $1.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if kinds.isEmpty {
                ContentUnavailableView("No output yet", systemImage: "text.alignleft",
                                       description: Text("Start a service to see its logs here."))
            } else {
                Picker("Service", selection: Binding(get: { selected ?? kinds[0] }, set: { selected = $0 })) {
                    ForEach(kinds, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                let lines = model.processes.logs[ServiceID(projectID: project.id, kind: selected ?? kinds[0])] ?? []
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                                Text(PortParser.stripANSI(line))
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(i)
                            }
                        }
                        .padding(12)
                    }
                    .background(.black.opacity(0.25), in: .rect(cornerRadius: 14))
                    .onChange(of: lines.count) { _, count in if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) } }
                }
            }
        }
    }
}
