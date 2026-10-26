import SwiftUI
import AppKit
import NexCore
import NexGit

struct SettingsPage: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    let section: SettingsSection
    @State private var selected: SettingsSection

    init(model: AppModel, section: SettingsSection) {
        self.model = model
        self.section = section
        _selected = State(initialValue: section)
    }

    private func symbol(_ s: SettingsSection) -> String {
        switch s {
        case .profile: return "person.crop.circle"
        case .git: return "arrow.triangle.branch"
        case .ai: return "sparkles"
        case .appearance: return "paintpalette"
        case .notifications: return "bell"
        case .general: return "gearshape"
        case .projects: return "square.grid.2x2"
        }
    }

    private var settingsHero: some View {
        let copy: (String, String, IllustrationKind) = {
            switch selected {
            case .profile: return ("You, at a glance", "Your name greets you every day and appears on your avatar.", .power)
            case .ai: return ("Your AI assistant", "Choose the default agent, how much it may do on its own, and a custom agent command.", .robot)
            case .git: return ("Git, your way", "Set who you commit as and how Pull behaves for every repository.", .branchGraph)
            case .appearance: return ("Make it yours", "Light or dark, and an accent. The default uses the nexventures.net colours.", .swatches)
            case .notifications: return ("Stay in the loop", "Hear when a server is ready, when one stops, and when an agent finishes.", .widgets)
            case .general: return ("The basics", "Start-up, the Dock icon and where your projects live.", .terminal)
            case .projects: return ("Your projects", "Pin favourites for the widget and adjust how each service starts.", .folders)
            }
        }()
        return HeroBanner(eyebrow: selected.rawValue, title: copy.0, subtitle: copy.1, illustration: copy.2)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(SettingsSection.allCases) { s in
                    Button { selected = s } label: {
                        Label(s.rawValue, systemImage: symbol(s))
                            .font(.callout.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .foregroundStyle(selected == s ? theme.accent : theme.fg)
                            .background(selected == s ? theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .frame(width: 210).padding(24)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    settingsHero
                    switch selected {
                    case .profile: ProfileSection(model: model)
                    case .git: GitSection(model: model)
                    case .ai: AISection(model: model)
                    case .appearance: AppearanceSection(model: model)
                    case .notifications: NotificationsSection(model: model)
                    case .general: GeneralSection(model: model)
                    case .projects: ProjectsSection(model: model)
                    }
                }
                .padding(.vertical, 28).padding(.trailing, 32)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.page = .home } label: { Label("Projects", systemImage: "chevron.left") }
                    .help("Back to projects")
            }
        }
        .onChange(of: section) { _, new in selected = new }
    }
}

struct SettingsCard<Content: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    var footer: String? = nil
    let content: Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(theme.fg)
            CardSurface {
                VStack(alignment: .leading, spacing: 14) { content }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let footer { Text(footer).font(.caption).foregroundStyle(theme.fg3) }
        }
    }
}

// MARK: - Profile

private struct ProfileSection: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        SettingsCard("Profile") {
            HStack(spacing: 18) {
                ProfileAvatar(settings: model.settings.settings, size: 88)
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Name", text: Binding(
                        get: { model.settings.settings.displayName },
                        set: { model.settings.settings.displayName = $0; model.settings.save() }))
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                    Text("Used in the greeting and on your avatar.").font(.caption).foregroundStyle(theme.fg3)
                    HStack {
                        Pill("Choose photo", style: .quiet) { choosePhoto() }
                        if model.settings.settings.avatarPhotoPath != nil {
                            Pill("Remove", style: .quiet) { model.settings.settings.avatarPhotoPath = nil; model.settings.save() }
                        }
                    }
                }
            }
            Divider().overlay(theme.line)
            Text("Avatar colour").font(.callout.weight(.medium)).foregroundStyle(theme.fg)
            HStack(spacing: 10) {
                swatch(nil)
                ForEach(AvatarPalette.hexes, id: \.self) { swatch($0) }
            }
        }
    }

    private func swatch(_ hex: String?) -> some View {
        let color: Color = hex.map { let c = HexColor(hex: $0); return Color(red: c.red, green: c.green, blue: c.blue) } ?? theme.accent
        let selected = model.settings.settings.avatarColorHex == hex
        return Button { model.settings.settings.avatarColorHex = hex; model.settings.save() } label: {
            Circle().fill(color).frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(theme.fg, lineWidth: selected ? 2 : 0).padding(-3))
        }
        .buttonStyle(.plain).help(hex == nil ? "Theme colour" : hex!)
    }

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let dest = AppSettings.supportDirectory.appendingPathComponent("avatar.\(url.pathExtension.lowercased())")
        try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dest)
        if (try? FileManager.default.copyItem(at: url, to: dest)) != nil {
            model.settings.settings.avatarPhotoPath = dest.path
            model.settings.save()
        }
    }
}

// MARK: - Git

private struct GitSection: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    @State private var name = ""
    @State private var email = ""
    @State private var branch = ""
    @State private var helper: String?
    @State private var message: String?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard("Identity", footer: "Stored in your global git configuration. Every repository uses it unless it has its own.") {
                TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                TextField("Email", text: $email).textFieldStyle(.roundedBorder)
                HStack {
                    Pill("Save identity") { Task { await saveIdentity() } }
                        .opacity(canSaveIdentity ? 1 : 0.4).disabled(!canSaveIdentity)
                    if let message { Text(message).font(.callout).foregroundStyle(failed ? .red : theme.fg2) }
                }
            }
            SettingsCard("New repositories") {
                HStack {
                    TextField("Default branch", text: $branch).textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                    Pill("Save", style: .quiet) { Task { await saveBranch() } }
                }
                Picker("When you press Pull", selection: Binding(
                    get: { model.settings.settings.defaultPullStrategy },
                    set: { model.settings.settings.defaultPullStrategy = $0; model.settings.save() })) {
                    Text("Fast-forward only (safest)").tag(PullPreference.ffOnly)
                    Text("Merge").tag(PullPreference.merge)
                    Text("Rebase").tag(PullPreference.rebase)
                }
            }
            SettingsCard("Sign-in", footer: "NexLauncher never stores passwords or tokens. It uses the credentials git already has.") {
                Label(helper.map { "Credential helper: \($0)" } ?? "No credential helper configured — https pushes will fail until you set one up.",
                      systemImage: helper == nil ? "exclamationmark.triangle" : "checkmark.shield")
                    .foregroundStyle(helper == nil ? .orange : theme.fg2)
            }
            SettingsCard("Tips") {
                Pill("Show dismissed tips again", style: .quiet) { model.resetTips() }
            }
        }
        .task { await load() }
    }

    private var canSaveIdentity: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !email.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func load() async {
        let snap = await model.loadGitSettings()
        name = snap.name ?? ""
        email = snap.email ?? ""
        branch = snap.defaultBranch ?? model.settings.settings.defaultBranch
        helper = snap.credentialHelper
    }

    private func saveIdentity() async {
        do {
            try await model.saveGitIdentity(name: name.trimmingCharacters(in: .whitespaces), email: email.trimmingCharacters(in: .whitespaces))
            failed = false; message = "Saved."
        } catch { failed = true; message = error.localizedDescription }
    }

    private func saveBranch() async {
        do { try await model.saveDefaultBranch(branch); failed = false; message = "Default branch saved." }
        catch { failed = true; message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }
}

// MARK: - Appearance

private struct AppearanceSection: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard("Appearance") {
                Picker("", selection: Binding(get: { model.settings.settings.appearance }, set: { model.setAppearance($0) })) {
                    Label("System", systemImage: "circle.lefthalf.filled").tag(AppearanceMode.system)
                    Label("Light", systemImage: "sun.max").tag(AppearanceMode.light)
                    Label("Dark", systemImage: "moon").tag(AppearanceMode.dark)
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
            }
            SettingsCard("Theme", footer: "Themes change the accent colour. The Nexventures theme uses the colours from nexventures.net.") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                    ForEach(ThemeID.allCases, id: \.self) { id in
                        ThemeSwatchCard(id: id, selected: model.settings.settings.theme == id) { model.setTheme(id) }
                    }
                }
            }
        }
    }
}

struct ThemeSwatchCard: View {
    @Environment(\.theme) private var theme
    let id: ThemeID
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let p = ThemeCatalog.palette(id, dark: theme.dark)
        func c(_ h: HexColor) -> Color { Color(red: h.red, green: h.green, blue: h.blue) }
        return Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(c(p.canvas))
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 6).fill(c(p.surface)).frame(width: 46, height: 30)
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(c(p.line)))
                        Capsule().fill(c(p.accent)).frame(width: 40, height: 16)
                        Circle().fill(c(p.accentSoft)).frame(width: 16, height: 16)
                    }
                    .padding(10)
                }
                .frame(height: 72)
                HStack {
                    Text(ThemeCatalog.displayNames[id] ?? id.rawValue).font(.callout.weight(.semibold)).foregroundStyle(theme.fg)
                    Spacer()
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent) }
                }
            }
            .padding(10)
            .background(theme.canvas, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? theme.accent : theme.line, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AI

private struct AISection: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard("Default agent") {
                Picker("Agent", selection: Binding(get: { model.settings.settings.defaultAgent },
                                                   set: { model.settings.settings.defaultAgent = $0; model.settings.save() })) {
                    ForEach(AgentKind.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Autonomy", selection: Binding(get: { model.settings.settings.agentAutonomy },
                                                      set: { model.settings.settings.agentAutonomy = $0; model.settings.save() })) {
                    ForEach(AgentAutonomy.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(model.settings.settings.agentAutonomy.explanation).font(.caption).foregroundStyle(theme.fg2)
            }
            SettingsCard("Custom agent", footer: "Any command-line agent. NexLauncher runs it in the project folder with the task in the variable $NEX_TASK (quoted for you if you leave it out).") {
                TextField(#"e.g. aider --message "$NEX_TASK""#, text: Binding(get: { model.settings.settings.customAgentCommand },
                                                                            set: { model.settings.settings.customAgentCommand = $0; model.settings.save() }))
                    .textFieldStyle(.roundedBorder).font(.system(.callout, design: .monospaced))
            }
            SettingsCard("Sign-in", footer: "Each agent keeps its own sign-in. NexLauncher never sees or stores your keys.") {
                ForEach(AgentKind.allCases.filter { $0.signInCommand != nil }) { kind in
                    HStack {
                        Text(kind.displayName).foregroundStyle(theme.fg)
                        Spacer()
                        Pill("Sign in", style: .quiet) { model.signIn(kind) }
                    }
                }
            }
        }
    }
}

// MARK: - Notifications

private struct NotificationsSection: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    private func binding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(get: { model.settings.settings[keyPath: keyPath] },
                set: { model.settings.settings[keyPath: keyPath] = $0; model.settings.save() })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard("Notifications", footer: "NexLauncher asks macOS for permission the first time you turn this on.") {
                Toggle("Notify me about my projects", isOn: Binding(
                    get: { model.settings.settings.notificationsEnabled },
                    set: { on in Task { await model.setNotificationsEnabled(on) } }))
                if model.notificationStatus == .denied {
                    HStack {
                        Label("macOS is blocking notifications for NexLauncher.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Spacer()
                        Pill("Open System Settings", style: .quiet) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
                        }
                    }
                }
            }
            SettingsCard("What to tell me") {
                Toggle("A service is ready (its port is up)", isOn: binding(\.notifyReady))
                Toggle("A service stopped unexpectedly", isOn: binding(\.notifyCrash))
                Toggle("A project was created or cloned", isOn: binding(\.notifyAdded))
                Toggle("An AI agent finished a task", isOn: binding(\.notifyAgents))
                Divider().overlay(theme.line)
                Toggle("Only when NexLauncher isn't in front", isOn: binding(\.notifyOnlyInBackground))
            }
            .disabled(!model.settings.settings.notificationsEnabled)
            .opacity(model.settings.settings.notificationsEnabled ? 1 : 0.5)
            SettingsCard("Try it") {
                Pill("Send a test notification", style: .quiet) { Task { await model.sendTestNotification() } }
            }
        }
        .task { await model.refreshNotificationStatus() }
    }
}

// MARK: - General

private struct GeneralSection: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard("Startup") {
                Toggle("Launch NexLauncher when I log in", isOn: Binding(get: { model.login.isEnabled }, set: { model.login.set($0) }))
                if let error = model.login.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
                Toggle("Show icon in the Dock", isOn: Binding(
                    get: { model.settings.settings.showDockIcon },
                    set: { model.settings.settings.showDockIcon = $0; model.settings.save(); model.applyDockIconPolicy() }))
            }
            SettingsCard("Projects folder", footer: "NexLauncher scans this folder, up to four levels deep.") {
                HStack {
                    Text(model.settings.settings.scanRoot.path).lineLimit(1).truncationMode(.middle).foregroundStyle(theme.fg2)
                    Spacer()
                    Pill("Choose…", style: .quiet) { chooseFolder() }
                }
            }
            SettingsCard("Menu bar", footer: "macOS hides menu bar icons when the bar is full (common with a notch). The shortcut always works.") {
                HStack {
                    Image(systemName: "bolt.horizontal.circle.fill").foregroundStyle(theme.accent)
                    Text("Open the quick panel from anywhere with ⌥⌘L").foregroundStyle(theme.fg)
                }
            }
            SettingsCard("Welcome") {
                HStack {
                    Text("Replay the first-launch walkthrough.").foregroundStyle(theme.fg2)
                    Spacer()
                    Pill("Show welcome again", style: .quiet) { model.replayOnboarding() }
                }
            }
            SettingsCard("Widgets") {
                HStack {
                    Text(model.settings.settings.widgetsConfirmed ? "Widgets added." : "Add Running Services or Quick Launch to your desktop.")
                        .foregroundStyle(theme.fg2)
                    Spacer()
                    Pill("How to add", style: .quiet) { model.sheet = .widgetsHowTo }
                }
            }
        }
        .onAppear { model.login.refresh() }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = model.settings.settings.scanRoot
        if panel.runModal() == .OK, let url = panel.url {
            model.settings.settings.scanRoot = url
            model.settings.save()
            Task { await model.refresh() }
        }
    }
}

// MARK: - Projects

private struct ProjectsSection: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard("Pinned for the Quick Launch widget") {
                if model.projects.isEmpty { Text("No projects yet").foregroundStyle(theme.fg2) }
                ForEach(model.projects) { project in
                    Toggle(project.name, isOn: Binding(
                        get: { model.settings.settings.pinnedProjectIDs.contains(project.id) },
                        set: { on in
                            var ids = model.settings.settings.pinnedProjectIDs.filter { $0 != project.id }
                            if on { ids.append(project.id) }
                            model.settings.settings.pinnedProjectIDs = ids
                            model.settings.save()
                            model.publishSnapshot()
                        }))
                }
            }
            SettingsCard("Commands and ports", footer: "Override how a service starts. Leave the command as detected to clear an override.") {
                ForEach(model.projects) { project in
                    ForEach(project.targets, id: \.self) { target in
                        OverrideRow(model: model, target: target, projectName: project.name)
                    }
                }
            }
        }
    }
}

private struct OverrideRow: View {
    let model: AppModel
    let target: ServiceTarget
    let projectName: String
    @State private var command = ""
    @State private var port = ""

    private var key: String { OverrideStore.key(directory: target.directory, kind: target.kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(projectName) · \(target.kind.rawValue)").font(.callout.weight(.medium))
            TextField("Command", text: $command, onCommit: save).font(.system(.caption, design: .monospaced)).textFieldStyle(.roundedBorder)
            TextField("Port (optional)", text: $port, onCommit: save).frame(width: 140).textFieldStyle(.roundedBorder)
        }
        .onAppear {
            let o = model.overrides.override(forPath: key)
            command = o?.command ?? target.command
            port = o?.port.map(String.init) ?? ""
        }
    }

    private func save() {
        let detected = CommandBuilder.command(for: target.kind, at: target.directory, framework: target.framework, flutterDevice: "macos")
        model.overrides.set(Override.edited(command: command, port: port, defaultCommand: detected), forPath: key)
        Task { await model.refresh() }
    }
}
