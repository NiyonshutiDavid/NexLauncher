import SwiftUI
import NexCore
import NexGit

struct GitPanelView: View {
    let model: AppModel
    let project: Project
    @State private var repos: [URL] = []
    @State private var selectedRepo: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if repos.isEmpty {
                ContentUnavailableView("No git repository", systemImage: "arrow.triangle.branch",
                                       description: Text("\(project.name) isn't a git repository yet."))
            } else {
                if repos.count > 1 {
                    Picker("Repository", selection: Binding(get: { selectedRepo ?? repos[0] }, set: { selectedRepo = $0 })) {
                        ForEach(repos, id: \.self) { Text(relativeName($0)).tag($0) }
                    }
                    .frame(maxWidth: 360)
                }
                RepoView(model: model, repo: selectedRepo ?? repos[0])
                    .id(selectedRepo ?? repos[0])
            }
        }
        .task { repos = model.git.findRepos(under: project.root) }
    }

    private func relativeName(_ url: URL) -> String {
        url == project.root ? project.name : url.path.replacingOccurrences(of: project.root.path + "/", with: "")
    }
}

private struct RepoView: View {
    let model: AppModel
    @State private var git: GitModel
    @State private var tab = 0
    @State private var showIdentity = false
    @State private var newBranch = ""
    @State private var showNewBranch = false
    @State private var discardTarget: FileChange?

    init(model: AppModel, repo: URL) {
        self.model = model
        _git = State(initialValue: GitModel(repo: repo, service: model.git))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toolbar
            if let error = git.errorMessage {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).textSelection(.enabled).font(.callout)
                    Spacer()
                    if git.pendingPullChoice {
                        Button("Merge") { Task { await git.pull(strategy: .merge) } }.buttonStyle(.glass)
                        Button("Rebase") { Task { await git.pull(strategy: .rebase) } }.buttonStyle(.glass)
                    }
                    Button { git.dismissPullChoice() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
                .padding(12)
                .glassEffect(.regular.tint(.orange.opacity(0.25)), in: .rect(cornerRadius: 14))
            }
            if git.needsIdentity && git.status != nil {
                HStack {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                    Text("Set your name and email before committing.")
                    Spacer()
                    Button("Set up") { showIdentity = true }.buttonStyle(.glassProminent)
                }
                .padding(12)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
            }
            Picker("", selection: $tab) { Text("Changes").tag(0); Text("History").tag(1) }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 240)
            if tab == 0 { changes } else { historyList }
        }
        .task { await git.reload() }
        .sheet(isPresented: $showIdentity) {
            IdentitySheet(current: git.identity) { id, scope in Task { await git.saveIdentity(id, scope: scope) } }
        }
        .alert("New branch", isPresented: $showNewBranch) {
            TextField("Branch name", text: $newBranch)
            Button("Create") { let n = newBranch; newBranch = ""; Task { await git.createBranch(n) } }
            Button("Cancel", role: .cancel) { newBranch = "" }
        }
        .confirmationDialog("Discard changes to \(discardTarget?.path ?? "")?", isPresented: Binding(
            get: { discardTarget != nil }, set: { if !$0 { discardTarget = nil } }), presenting: discardTarget) { file in
            Button("Discard changes", role: .destructive) { Task { await git.discard(file) } }
        } message: { _ in Text("This can't be undone.") }
    }

    // MARK: - Pieces

    private var toolbar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(git.branches, id: \.self) { b in Button(b) { Task { await git.switchBranch(b) } } }
                Divider()
                Button("New branch…") { showNewBranch = true }
            } label: {
                Label(git.status?.branch ?? (git.status?.isDetached == true ? "detached HEAD" : "—"), systemImage: "arrow.triangle.branch")
            }
            .buttonStyle(.glass)
            .fixedSize()
            if let s = git.status {
                if s.ahead > 0 { Badge(text: "↑\(s.ahead)", tint: .blue) }
                if s.behind > 0 { Badge(text: "↓\(s.behind)", tint: .orange) }
            }
            Spacer()
            if git.isBusy { ProgressView().controlSize(.small) }
            Button { Task { await git.fetch() } } label: { Label("Fetch", systemImage: "arrow.clockwise") }.buttonStyle(.glass)
            Button { Task { await git.pull(strategy: .ffOnly) } } label: { Label("Pull", systemImage: "arrow.down.circle") }.buttonStyle(.glass)
            Button { Task { await git.push() } } label: { Label("Push", systemImage: "arrow.up.circle") }.buttonStyle(.glassProminent)
            Button { showIdentity = true } label: { Image(systemName: "person.crop.circle") }.buttonStyle(.glass).help("Git name and email")
        }
        .disabled(git.isBusy)
    }

    private var changes: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Toggle("", isOn: Binding(
                        get: { (git.status?.changes.isEmpty == false) && git.stagedCount == git.status?.changes.count },
                        set: { on in Task { await git.stageAll(on) } })).labelsHidden()
                    Text("\(git.status?.changes.count ?? 0) changed files").font(.callout.weight(.medium))
                }
                List(git.status?.changes ?? [], selection: Binding(
                    get: { git.selectedFile?.path }, set: { path in
                        if let f = git.status?.changes.first(where: { $0.path == path }) { Task { await git.select(f) } } })) { file in
                    HStack {
                        Toggle("", isOn: Binding(get: { file.isStaged }, set: { _ in Task { await git.toggleStage(file) } })).labelsHidden()
                        Text(file.path).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(statusLetter(file)).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    .tag(file.path)
                    .contextMenu { Button("Discard changes…", role: .destructive) { discardTarget = file } }
                }
                .listStyle(.plain)
                .frame(minHeight: 160)
                commitBox
            }
            .frame(width: 340)
            DiffView(text: git.diffText)
        }
        .frame(minHeight: 340)
    }

    private var commitBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Summary", text: Bindable(git).summary).textFieldStyle(.roundedBorder)
            TextField("Description", text: Bindable(git).descriptionText, axis: .vertical)
                .lineLimit(2...4).textFieldStyle(.roundedBorder)
            Button {
                Task { await git.commit() }
            } label: {
                Text("Commit \(git.stagedCount > 0 ? "\(git.stagedCount) file\(git.stagedCount == 1 ? "" : "s")" : "all")")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled((git.status?.changes.isEmpty ?? true) || git.isBusy)
        }
    }

    private var historyList: some View {
        List(git.history) { commit in
            VStack(alignment: .leading, spacing: 2) {
                Text(commit.subject).lineLimit(1)
                Text("\(commit.author) · \(commit.date.formatted(.relative(presentation: .named)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
        .frame(minHeight: 300)
    }

    private func statusLetter(_ f: FileChange) -> String {
        if f.isUntracked { return "U" }
        let c = f.index != "." ? f.index : f.worktree
        return String(c)
    }
}
