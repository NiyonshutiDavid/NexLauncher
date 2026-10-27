import Foundation
import Observation
import Adwaita
import NexApp
import NexCore
import NexGit

/// Re-renders the Git panel when its `GitModel` changes (as `AppState` does for the app model).
struct GitState: Model {
    var model: ModelData?
    var tick = 0
    let git: GitModel

    init(git: GitModel) { self.git = git }

    mutating func setup() { observe() }

    func observe() {
        withObservationTracking {
            _ = (git.status, git.branches, git.history, git.identity, git.selectedFile, git.diffText, git.isBusy,
                 git.pendingPullChoice, git.errorMessage, git.summary, git.descriptionText)
        } onChange: {
            MainActor.assumeIsolated { Idle { setModel { $0.tick &+= 1 }; observe() } }
        }
    }
}

/// Stage, commit, pull, push, branches and history for one repository (the Mac Git tab).
struct GitPanel: View {
    let model: AppModel
    @State private var state: GitState
    @State private var identityOpen = false
    @State private var newBranch = ""
    @State private var loaded = false

    init(model: AppModel, repo: URL) {
        self.model = model
        self._state = State(wrappedValue: GitState(git: GitModel(repo: repo, service: model.git)))
    }

    private var git: GitModel { state.git }

    var view: Body {
        VStack(spacing: 12) {
            if git.needsIdentity {
                Banner("Set your name and email before committing.", visible: true)
                    .button("Set up") { identityOpen = true }
            }
            HStack(spacing: 6) {
                Text(branchLine).style("heading").halign(.start).hexpand()
                Button("Fetch") { Task { await git.fetch() } }.pill()
                Button("Pull") { Task { await git.pull(strategy: model.settings.settings.defaultPullStrategy.strategy) } }.pill()
                Button("Push") { Task { await git.push() } }.suggested().pill()
            }
            if git.pendingPullChoice {
                HStack(spacing: 6) {
                    Text("The branches have diverged.").halign(.start).hexpand()
                    Button("Merge") { Task { await git.pull(strategy: .merge) } }.pill()
                    Button("Rebase") { Task { await git.pull(strategy: .rebase) } }.pill()
                    Button("Cancel") { git.dismissPullChoice() }.flat()
                }
            }
            if let error = git.errorMessage { Text(error).style("error").wrap().halign(.start) }
            changes
            commitBox
            if !git.diffText.isEmpty {
                Text(git.diffText).style("monospace").selectable(true).halign(.start).padding(12).style("card")
            }
            history
        }
        .dialog(visible: $identityOpen, title: "Git name and email", width: 420, height: 300) {
            IdentityDialogContent(current: git.identity) { identity, scope in
                identityOpen = false
                Task { await git.saveIdentity(identity, scope: scope) }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            Task { await git.reload() }
        }
    }

    private var branchLine: String {
        guard let status = git.status else { return "Loading…" }
        var text = status.branch ?? "No branch"
        if status.ahead > 0 { text += "  ↑\(status.ahead)" }
        if status.behind > 0 { text += "  ↓\(status.behind)" }
        return text
    }

    private var changes: AnyView {
        Form {
            ForEach(git.status?.changes ?? []) { change in
                ActionRow(change.path)
                    .subtitle(change.isUntracked ? "New" : change.isStaged ? "Staged" : "Changed")
                    .suffix {
                        Toggle("Stage", isOn: Binding(get: { change.isStaged }, set: { _ in Task { await git.toggleStage(change) } }))
                            .valign(.center)
                    }
                    .onClick { Task { await git.select(change) } }
            }
        }
    }

    private var commitBox: AnyView {
        Form {
            EntryRow("Summary", text: Binding(get: { git.summary }, set: { git.summary = $0 }))
            EntryRow("Description", text: Binding(get: { git.descriptionText }, set: { git.descriptionText = $0 }))
            ButtonRow().title("Commit \(git.stagedCount) staged").activated { Task { await git.commit() } }
        }
    }

    private var history: AnyView {
        Form {
            ForEach(Array(git.history.prefix(30))) { commit in
                ActionRow(commit.subject).subtitle("\(commit.author)  \(commit.date.formatted(date: .abbreviated, time: .shortened))")
            }
        }
    }
}

/// Name and email for git, for this repository or every repository.
struct IdentityDialogContent: View {
    let current: GitIdentity
    let onSave: (GitIdentity, GitScope) -> Void
    @State private var name = ""
    @State private var email = ""
    @State private var everywhere = true

    var view: Body {
        VStack(spacing: 12) {
            Form {
                EntryRow("Name", text: $name)
                EntryRow("Email", text: $email)
                SwitchRow("Use for every repository", isOn: $everywhere)
            }
            Button("Save") { onSave(GitIdentity(name: name, email: email), everywhere ? .global : .repo) }
                .suggested().pill().halign(.end)
        }
        .padding(20)
        .onAppear {
            if name.isEmpty { name = current.name ?? "" }
            if email.isEmpty { email = current.email ?? "" }
        }
    }
}
