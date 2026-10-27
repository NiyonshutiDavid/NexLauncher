import SwiftUI
import NexCore
import NexApp

/// "Set up <project>": what will be installed, live progress, and the reason if something fails.
struct SetupSheet: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    let session: SetupSession

    private var current: SetupSession { model.setup ?? session }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                AnimatedIllustration(kind: .rocket, amplitude: isRunning ? 6 : 3).frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 4) {
                    Text(isRunning ? "Setting up \(current.project.name)…" : "Set up \(current.project.name)")
                        .font(.title2.weight(.bold)).foregroundStyle(theme.fg)
                    Text(subtitle).foregroundStyle(theme.fg2).fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(current.steps) { step in
                    HStack(alignment: .top, spacing: 12) {
                        statusIcon(step.status).frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title).font(.callout.weight(.semibold)).foregroundStyle(theme.fg)
                            Text(step.command).font(.caption.monospaced()).foregroundStyle(theme.fg3).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let line = model.setupLastLine {
                Text(line).font(.caption.monospaced()).foregroundStyle(theme.fg2).lineLimit(2)
                    .transition(.opacity)
            }
            if case .failed(let reason) = current.phase {
                Label(reason, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                switch current.phase {
                case .confirm:
                    Button("Cancel") { model.cancelInstall() }.keyboardShortcut(.cancelAction)
                    Pill("Set up and run", systemImage: "sparkles") { Task { await model.confirmInstall() } }
                        .keyboardShortcut(.defaultAction)
                case .running:
                    Pill("Stop", style: .destructive) { Task { await model.stop(current.project) } }
                case .failed:
                    Button("Close") { model.cancelInstall() }.keyboardShortcut(.cancelAction)
                    Pill("Open logs", style: .quiet) {
                        model.cancelInstall(); model.page = .project(current.project.id); model.detailTab = .logs
                    }
                }
            }
        }
        .padding(26)
        .frame(width: 520)
        .background(theme.surface)
        .interactiveDismissDisabled(isRunning)
        .animation(.easeInOut(duration: 0.2), value: model.setupLastLine)
    }

    private var isRunning: Bool { current.phase == .running }

    private var subtitle: String {
        switch current.phase {
        case .confirm: return "\(current.project.name) needs its dependencies before it can run. This happens once."
        case .running: return "Installing what \(current.project.name) needs. It starts as soon as this is done."
        case .failed: return "Setup stopped. Fix the problem below and try again."
        }
    }

    @ViewBuilder private func statusIcon(_ status: SetupStep.Status) -> some View {
        switch status {
        case .pending: Image(systemName: "circle.dashed").foregroundStyle(theme.fg3)
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}
