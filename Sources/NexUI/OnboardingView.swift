import SwiftUI
import AppKit
import NexCore

struct OnboardingView: View {
    @Bindable var model: AppModel
    @State private var ob: OnboardingModel
    @Environment(\.theme) private var theme

    init(model: AppModel) {
        self.model = model
        _ob = State(initialValue: OnboardingModel(model: model))
    }

    var body: some View {
        ZStack {
            theme.canvas.ignoresSafeArea()
            // soft accent glows behind the card
            Circle().fill(theme.accent.opacity(theme.dark ? 0.22 : 0.16)).frame(width: 520).blur(radius: 110).offset(x: -300, y: -200)
            Circle().fill(theme.accent.opacity(theme.dark ? 0.14 : 0.10)).frame(width: 420).blur(radius: 100).offset(x: 320, y: 220)

            HStack(spacing: 0) {
                VStack {
                    Spacer()
                    IllustrationView(ob.step.illustration).frame(width: 230, height: 230)
                        .id(ob.step)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                    Spacer()
                    HStack(spacing: 7) {
                        ForEach(OnboardingStep.allCases, id: \.self) { s in
                            Capsule().fill(s == ob.step ? theme.accent : theme.line)
                                .frame(width: s == ob.step ? 22 : 7, height: 7)
                        }
                    }
                    .padding(.bottom, 26)
                }
                .frame(width: 300)
                .frame(maxHeight: .infinity)
                .background(LinearGradient(colors: [theme.accentSoft, theme.surface], startPoint: .top, endPoint: .bottom))

                VStack(alignment: .leading, spacing: 18) {
                    content.id(ob.step).transition(.opacity)
                    Spacer(minLength: 0)
                    footer
                }
                .padding(34)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface)
            }
            .frame(width: 880, height: 540)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(theme.dark ? 0.5 : 0.14), radius: 40, y: 18)
        }
        .animation(.easeInOut(duration: 0.25), value: ob.step)
        .task { await ob.loadExisting() }
    }

    // MARK: - Steps

    @ViewBuilder private var content: some View {
        switch ob.step {
        case .welcome:
            title("Welcome to NexLauncher", "Run, manage and ship all your Nexventures projects from one place.")
            VStack(alignment: .leading, spacing: 12) {
                bullet("play.circle.fill", "Start any frontend, backend or Flutter app with one click")
                bullet("terminal.fill", "A real terminal inside every project folder")
                bullet("arrow.triangle.branch", "Commit, pull and push without leaving the app")
                bullet("pin.fill", "Pin favourites to the menu bar, the Dock and your desktop widget")
            }
        case .name:
            title("What should we call you?", "It appears in your greeting and on your profile.")
            HStack(spacing: 16) {
                ProfileAvatar(settings: previewSettings, size: 64)
                TextField("Your name", text: $ob.name).textFieldStyle(.roundedBorder).font(.title3).frame(maxWidth: 300)
                    .onSubmit { ob.next() }
            }
        case .projects:
            title("Where are your projects?", "NexLauncher looks in this folder, up to four levels deep, and finds apps by their manifests.")
            HStack {
                Image(systemName: "folder.fill").foregroundStyle(theme.accent)
                Text(ob.folder.path).lineLimit(1).truncationMode(.middle).foregroundStyle(theme.fg)
                Spacer()
                Pill("Choose…", style: .quiet) { chooseFolder() }
            }
            .padding(12).background(theme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Group {
                if !ob.folderExists {
                    Label("That folder doesn't exist.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } else if let n = ob.detectedCount {
                    Label(n == 0 ? "No projects found yet — you can add some later." : "Found \(n) project\(n == 1 ? "" : "s").",
                          systemImage: n == 0 ? "tray" : "checkmark.circle.fill").foregroundStyle(n == 0 ? theme.fg2 : .green)
                } else {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Looking…").foregroundStyle(theme.fg2) }
                }
            }
            .task(id: ob.folder) { await ob.scanFolder() }
        case .git:
            title("Tell git who you are", "Your commits carry this name and email. You can skip this and set it later in Settings.")
            TextField("Name", text: $ob.gitName).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
            TextField("Email", text: $ob.gitEmail).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
            Text("Saved to your global git configuration. NexLauncher never stores passwords or tokens.")
                .font(.caption).foregroundStyle(theme.fg3)
        case .look:
            title("Make it yours", "Pick light or dark, and an accent. The default uses the colours of nexventures.net.")
            Picker("", selection: $ob.appearance) {
                Label("System", systemImage: "circle.lefthalf.filled").tag(AppearanceMode.system)
                Label("Light", systemImage: "sun.max").tag(AppearanceMode.light)
                Label("Dark", systemImage: "moon").tag(AppearanceMode.dark)
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 340)
            .onChange(of: ob.appearance) { _, new in model.setAppearance(new) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(ThemeID.allCases, id: \.self) { id in
                    ThemeSwatchCard(id: id, selected: ob.theme == id) { ob.theme = id; model.setTheme(id) }
                }
            }
        case .extras:
            title("Stay in the loop", "Two optional things that make NexLauncher feel at home.")
            Toggle("Notify me when a service is ready or stops unexpectedly", isOn: $ob.notifications)
            Toggle("Open NexLauncher when I log in", isOn: $ob.launchAtLogin)
            Text("Tip: pin a project with the pin button to see it in the menu bar, the Dock menu and the Quick Launch widget.")
                .font(.callout).foregroundStyle(theme.fg2)
        }
    }

    private var footer: some View {
        HStack {
            if !ob.isFirst { Button("Back") { ob.back() }.buttonStyle(.plain).foregroundStyle(theme.fg2) }
            Spacer()
            if !ob.isLast { Button("Skip setup") { model.skipOnboarding() }.buttonStyle(.plain).foregroundStyle(theme.fg3) }
            Pill(ob.isLast ? "Finish" : ob.isFirst ? "Get started" : "Continue") {
                if ob.isLast { Task { await ob.finish() } } else { ob.next() }
            }
            .opacity(ob.canAdvance && !ob.isFinishing ? 1 : 0.4)
            .disabled(!ob.canAdvance || ob.isFinishing)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Helpers

    private var previewSettings: AppSettings {
        var s = model.settings.settings
        s.displayName = ob.name
        return s
    }

    private func title(_ headline: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headline).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(theme.fg)
            Text(body).font(.title3).foregroundStyle(theme.fg2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(theme.accent).frame(width: 24)
            Text(text).foregroundStyle(theme.fg)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = ob.folder
        if panel.runModal() == .OK, let url = panel.url { ob.folder = url }
    }
}
