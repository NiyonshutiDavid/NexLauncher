import Foundation
import Observation
import Adwaita
import NexApp
import NexCore
import NexGit

/// Profile, git, AI, appearance, notifications and general settings (the Mac Settings page, without the Dock and
/// widget options that don't exist on Linux).
struct SettingsPage: View {
    let model: AppModel
    @State private var identityOpen = false

    private func setting<T>(_ key: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { model.settings.settings[keyPath: key] },
                set: { model.settings.settings[keyPath: key] = $0; model.settings.save() })
    }

    var view: Body {
        ScrollView {
            VStack(spacing: 18) {
                Text("Settings").style("title-1").halign(.start)
                FormSection("Profile") {
                    Form { EntryRow("Name", text: setting(\.displayName)) }
                }
                FormSection("Git") {
                    Form {
                        ActionRow("Name and email").subtitle(model.gitIdentitySet ? "Set" : "Not set yet")
                            .suffix { Button("Edit") { identityOpen = true }.flat().valign(.center) }
                        EntryRow("Default branch for new repositories", text: setting(\.defaultBranch))
                    }
                }
                FormSection("AI") {
                    Form {
                        ComboRow("Default agent", selection: Binding(get: { model.settings.settings.defaultAgent.rawValue },
                                                                      set: { model.settings.settings.defaultAgent = AgentKind(rawValue: $0) ?? .claude; model.settings.save() }),
                                 values: AgentKind.allCases.map { ChoiceItem(id: $0.rawValue) })
                        EntryRow("Custom agent command", text: setting(\.customAgentCommand))
                    }
                }
                FormSection("Appearance") {
                    Form {
                        ComboRow("Appearance", selection: Binding(get: { model.settings.settings.appearance.rawValue },
                                                                   set: { model.settings.settings.appearance = AppearanceMode(rawValue: $0) ?? .system; model.settings.save() }),
                                 values: AppearanceMode.allCases.map { ChoiceItem(id: $0.rawValue) })
                    }
                }
                FormSection("General") {
                    Form {
                        SwitchRow("Launch at login", isOn: Binding(get: { model.login.isEnabled }, set: { model.login.set($0) }))
                        SwitchRow("Notifications", isOn: setting(\.notificationsEnabled))
                        ActionRow("Projects folder").subtitle(model.settings.settings.scanRoot.path)
                    }
                    if let error = model.login.errorMessage { Text(error).style("error").halign(.start) }
                }
                Button("Show welcome again") { model.replayOnboarding() }.flat().halign(.start)
            }
            .padding(24)
            .frame(maxWidth: 760)
        }
        .topToolbar { BreadcrumbHeader(model: model) }
        .dialog(visible: $identityOpen, title: "Git name and email", width: 420, height: 300) {
            IdentityDialogContent(current: GitIdentity(name: nil, email: nil)) { identity, _ in
                identityOpen = false
                Task { try? await model.saveGitIdentity(name: identity.name ?? "", email: identity.email ?? "") }
            }
        }
    }
}

/// The first-launch walkthrough, shortened for Linux: name, projects folder (create it if missing), git, finish.
struct OnboardingContent: View {
    let model: AppModel
    @State private var flow: OnboardingState

    init(model: AppModel) {
        self.model = model
        self._flow = State(wrappedValue: OnboardingState(flow: OnboardingModel(model: model)))
    }

    private var f: OnboardingModel { flow.flow }

    var view: Body {
        VStack(spacing: 14) {
            Text(title(f.step)).style("title-1").halign(.start)
            switch f.step {
            case .name:
                Form { EntryRow("Your name", text: Binding(get: { f.name }, set: { f.name = $0 })) }
            case .projects:
                Form {
                    EntryRow("Projects folder", text: Binding(get: { f.folder.path }, set: { f.setFolder(path: $0) }))
                }
                if !f.folderExists {
                    Button("Create this folder") { try? f.createFolder() }.pill().halign(.start)
                }
            case .git:
                Form {
                    EntryRow("Git name", text: Binding(get: { f.gitName }, set: { f.gitName = $0 }))
                    EntryRow("Git email", text: Binding(get: { f.gitEmail }, set: { f.gitEmail = $0 }))
                }
            default:
                Text(f.step == .welcome
                     ? "NexLauncher finds the apps in your projects folder and runs them, with git, a terminal and AI agents built in."
                     : "You can change all of this later in Settings.").wrap(true).halign(.start)
            }
            HStack(spacing: 8) {
                if !f.isFirst { Button("Back") { f.back() }.pill() }
                Button("Skip") { model.skipOnboarding(); Task { await model.refresh() } }.flat()
                Button(f.isLast ? "Start" : "Next") {
                    if f.isLast { Task { await f.finish() } } else { f.next() }
                }
                .suggested().pill()
            }
            .halign(.end)
        }
        .padding(24)
    }

    private func title(_ step: OnboardingStep) -> String {
        switch step {
        case .welcome: return "Welcome to NexLauncher"
        case .name: return "What should we call you?"
        case .projects: return "Where are your projects?"
        case .git: return "Tell git who you are"
        default: return "Almost there"
        }
    }
}

/// Re-renders onboarding when its model changes.
struct OnboardingState: Model {
    var model: ModelData?
    var tick = 0
    let flow: OnboardingModel

    init(flow: OnboardingModel) { self.flow = flow }

    mutating func setup() { MainActor.assumeIsolated { observe() } }

    @MainActor func observe() {
        withObservationTracking {
            _ = (flow.step, flow.name, flow.folder, flow.gitName, flow.gitEmail, flow.isFinishing)
        } onChange: {
            MainActor.assumeIsolated { _ = Idle { setModel { $0.tick &+= 1 }; observe() } }
        }
    }
}
