import SwiftUI
import NexApp
import NexTerminal

/// Terminal tabs. New tabs open in `directory`; tabs opened elsewhere stay available here too.
struct TerminalPanel: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    let directory: URL
    /// Only used if the model was built without SwiftTerm tabs (never in the app).
    private static let noTabs = TerminalTabs()

    var body: some View {
        let tabs = model.terminalTabs ?? Self.noTabs
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tabs.sessions) { session in
                            HStack(spacing: 6) {
                                Image(systemName: "terminal").font(.caption)
                                Text(session.title).font(.caption.weight(.medium)).lineLimit(1)
                                Button { tabs.close(session.id) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                                    .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .foregroundStyle(tabs.selectedID == session.id ? theme.onAccent : theme.fg2)
                            .background(tabs.selectedID == session.id ? theme.accent : theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(theme.line, lineWidth: tabs.selectedID == session.id ? 0 : 1))
                            .onTapGesture { tabs.selectedID = session.id }
                        }
                    }
                }
                IconButton("plus", help: "New terminal in \(directory.lastPathComponent)") { tabs.open(at: directory) }
            }
            if let session = tabs.sessions.first(where: { $0.id == tabs.selectedID }) ?? tabs.sessions.last {
                TerminalHostView(session: session)
                    .id(session.id)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .frame(minHeight: 360)
            } else {
                VStack(spacing: 12) {
                    IllustrationView(.terminal).frame(width: 150, height: 150)
                    Text("Run things by hand").font(.title3.weight(.bold)).foregroundStyle(theme.fg)
                    Text("Open a real terminal in \(directory.lastPathComponent).").foregroundStyle(theme.fg2)
                    Pill("Open terminal") { tabs.open(at: directory) }
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        }
    }
}
