import SwiftUI
import NexCore
import NexApp
import NexProcess

struct LogPanel: View {
    @Bindable var model: AppModel
    let project: Project
    @State private var selected: ServiceID?

    private var ids: [ServiceID] {
        model.processes.logs.keys.filter { $0.projectID == project.id }
            .sorted { ($0.kind.rawValue, $0.directory) < ($1.kind.rawValue, $1.directory) }
    }

    private func label(_ id: ServiceID) -> String {
        let name = id.kind.rawValue.capitalized
        let same = ids.filter { $0.kind == id.kind }.count
        return same > 1 ? "\(name) · \(URL(fileURLWithPath: id.directory).lastPathComponent)" : name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if ids.isEmpty {
                ContentUnavailableView("No output yet", systemImage: "text.alignleft",
                                       description: Text("Start a service to see its logs here."))
            } else {
                Picker("Service", selection: Binding(get: { ids.contains(selected ?? ids[0]) ? (selected ?? ids[0]) : ids[0] }, set: { selected = $0 })) {
                    ForEach(ids, id: \.self) { Text(label($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                let lines = model.processes.logs[ids.contains(selected ?? ids[0]) ? (selected ?? ids[0]) : ids[0]] ?? []
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
