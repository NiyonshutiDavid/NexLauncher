import SwiftUI
import NexApp

struct DiffView: View {
    let text: String

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            if text.isEmpty {
                Text("Select a file to see its changes")
                    .foregroundStyle(.secondary).padding(20)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                        Text(String(line).isEmpty ? " " : String(line))
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(background(for: line))
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(.black.opacity(0.2), in: .rect(cornerRadius: 14))
    }

    private func background(for line: Substring) -> Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") { return .clear }
        if line.hasPrefix("+") { return .green.opacity(0.22) }
        if line.hasPrefix("-") { return .red.opacity(0.22) }
        if line.hasPrefix("@@") { return .blue.opacity(0.18) }
        return .clear
    }
}
