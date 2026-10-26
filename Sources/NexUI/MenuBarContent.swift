import SwiftUI
import AppKit
import NexCore

/// The menu bar popover: use NexLauncher without opening its window.
public struct MenuBarContent: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    @State private var query = ""

    public init(model: AppModel) { self.model = model }

    private var matches: [Project] { MenuBarFilter.matching(query, in: model.projects) }
    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !searching {
                        section("Pinned", model.pinnedProjects)
                        runningSection
                    }
                    section(searching ? "Results" : "All projects", matches, emptyText: model.projects.isEmpty ? "No projects found yet." : "No matches.")
                }
                .padding(14)
            }
            .frame(maxHeight: 400)
            if let message = model.statusMessage { notice(message) }
            Divider().overlay(theme.line)
            quickActions
            Divider().overlay(theme.line)
            controls
            Divider().overlay(theme.line)
            footer
        }
        .frame(width: 400)
        .background(theme.canvas)
        .task { if model.projects.isEmpty { await model.refresh() }; await model.refreshNotificationStatus() }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ProfileAvatar(settings: model.settings.settings, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.greeting).font(.headline).foregroundStyle(theme.fg)
                    Text(model.processes.runningCount > 0 ? "\(model.processes.runningCount) running" : "Nothing running")
                        .font(.caption).foregroundStyle(theme.fg2)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.fg3)
                TextField("Search projects", text: $query).textFieldStyle(.plain)
                if searching { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(theme.fg3) }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.line))
        }
        .padding(14)
    }

    @ViewBuilder private func section(_ title: String, _ projects: [Project], emptyText: String? = nil) -> some View {
        if !projects.isEmpty || emptyText != nil {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased()).font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(theme.fg3)
                if projects.isEmpty, let emptyText { Text(emptyText).font(.callout).foregroundStyle(theme.fg2).padding(.vertical, 8) }
                ForEach(projects) { MenuProjectRow(model: model, project: $0) }
            }
        }
    }

    @ViewBuilder private var runningSection: some View {
        let running = model.runningProjects
        if !running.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("RUNNING NOW").font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(theme.fg3)
                ForEach(running) { project in
                    HStack(spacing: 10) {
                        Circle().fill(.green).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(project.name).font(.callout.weight(.semibold)).foregroundStyle(theme.fg).lineLimit(1)
                            let ports = model.runningPorts(for: project)
                            Text(ports.isEmpty ? "Starting…" : ports.map { "localhost:\($0)" }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(theme.fg2)
                        }
                        Spacer()
                        if let port = model.runningPorts(for: project).first {
                            Button("Open") { NSWorkspace.shared.open(URL(string: "http://localhost:\(port)")!) }
                                .buttonStyle(.plain).font(.callout.weight(.semibold)).foregroundStyle(theme.accent)
                        }
                        Button("Logs") { model.page = .project(project.id); model.detailTab = .logs; model.showMainWindow() }
                            .buttonStyle(.plain).font(.callout).foregroundStyle(theme.fg2)
                        Pill("Stop", style: .destructive) { Task { await model.stop(project) } }
                    }
                    .padding(10)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private func notice(_ message: StatusMessage) -> some View {
        HStack(spacing: 8) {
            Image(systemName: message.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(message.isError ? .orange : .green)
            Text(message.text).font(.caption).foregroundStyle(theme.fg).lineLimit(3)
            Spacer()
            Button { model.dismissStatusMessage() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(theme.fg3)
        }
        .padding(10).background(theme.accentSoft)
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            quick("New project", "folder.badge.plus") { model.sheet = .addProject(.newFolder); model.showMainWindow() }
            quick("Clone", "arrow.down.circle") { model.sheet = .addProject(.clone); model.showMainWindow() }
            quick("Terminal", "terminal") {
                let root = model.settings.settings.scanRoot
                model.showTerminal(at: root, page: .folder(root.path)); model.showMainWindow()
            }
            quick("Refresh", "arrow.clockwise") { Task { await model.refresh() } }
        }
        .padding(12)
    }

    private func quick(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                Text(title).font(.caption2.weight(.medium))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .foregroundStyle(theme.accent)
            .background(theme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Notifications", isOn: Binding(
                get: { model.settings.settings.notificationsEnabled },
                set: { on in Task { await model.setNotificationsEnabled(on) } }))
            Toggle("Launch at login", isOn: Binding(get: { model.login.isEnabled }, set: { model.login.set($0) }))
            Picker("Appearance", selection: Binding(get: { model.settings.settings.appearance }, set: { model.setAppearance($0) })) {
                Text("System").tag(AppearanceMode.system)
                Text("Light").tag(AppearanceMode.light)
                Text("Dark").tag(AppearanceMode.dark)
            }
            .pickerStyle(.segmented)
        }
        .toggleStyle(.switch).controlSize(.small)
        .font(.callout)
        .padding(12)
    }

    private var footer: some View {
        HStack {
            Button("Open NexLauncher") { model.showMainWindow() }
            Button("Settings") { model.page = .settings(.general); model.showMainWindow() }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.plain).font(.callout.weight(.medium)).foregroundStyle(theme.accent)
        .padding(12)
    }
}

private struct MenuProjectRow: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    let project: Project
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            IconTile(name: project.name, glyph: ProjectGlyph.symbol(for: project), size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name).font(.callout.weight(.semibold)).foregroundStyle(theme.fg).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(subtitleColor).lineLimit(1)
            }
            Spacer(minLength: 6)
            if model.isRunning(project) {
                Pill("Stop", style: .destructive) { Task { await model.stop(project) } }
            } else {
                Menu {
                    ForEach(model.availableActions(for: project), id: \.self) { action in
                        Button(action.rawValue) {
                            if action == .flutter { model.page = .project(project.id); model.showMainWindow() }   // needs a device choice
                            else { Task { await model.run(project, kinds: action.kinds) } }
                        }
                    }
                } label: { PillLabel("Run", systemImage: "play.fill") } primaryAction: {
                    Task { await model.toggleRun(project) }
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            }
            Menu {
                Button(model.isPinned(project) ? "Unpin" : "Pin", systemImage: model.isPinned(project) ? "pin.slash" : "pin") { model.togglePin(project) }
                Divider()
                Button("Open Terminal Here", systemImage: "terminal") { model.showTerminal(at: project.root, page: .project(project.id)); model.showMainWindow() }
                Button("Show in NexLauncher", systemImage: "macwindow") { model.page = .project(project.id); model.detailTab = .overview; model.showMainWindow() }
                Button("Reveal in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([project.root]) }
                if let port = model.runningPorts(for: project).first {
                    Button("Open in Browser", systemImage: "safari") { NSWorkspace.shared.open(URL(string: "http://localhost:\(port)")!) }
                }
                Divider()
                Button("Git: Fetch", systemImage: "arrow.clockwise") { Task { await model.quickGit(.fetch, project: project) } }
                Button("Git: Pull", systemImage: "arrow.down.circle") { Task { await model.quickGit(.pull, project: project) } }
                Button("Git: Push", systemImage: "arrow.up.circle") { Task { await model.quickGit(.push, project: project) } }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .bold)).foregroundStyle(theme.fg2)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(hovering ? theme.accentSoft.opacity(0.7) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering = $0 }
    }

    private var detail: String {
        if let g = model.gitBadges[project.id], g.changes > 0 { return "\(g.changes) uncommitted · " + ProjectSubtitle.text(for: project) }
        return ProjectSubtitle.text(for: project)
    }
    private var subtitleColor: Color {
        (model.gitBadges[project.id]?.changes ?? 0) > 0 ? theme.accent : theme.fg2
    }
}
