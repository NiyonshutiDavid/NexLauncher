import Testing
import Foundation
import NexCore
import NexGit
@testable import NexUI

@MainActor
@Suite struct SettingsPageTests {
    private func modelWithTempGlobalGit() -> (AppModel, Sandbox, URL) {
        let sb = Sandbox()
        let config = sb.root.appendingPathComponent("gitconfig-global")
        FileManager.default.createFile(atPath: config.path, contents: nil)
        let git = GitService(runner: GitRunner(extraEnvironment: ["GIT_CONFIG_GLOBAL": config.path, "GIT_CONFIG_NOSYSTEM": "1"]))
        let settings = SettingsStore(fileURL: sb.root.appendingPathComponent("settings.json"))
        let model = AppModel(settings: settings,
                             overrides: OverrideStore(fileURL: sb.root.appendingPathComponent("o.json")),
                             git: git, login: FakeLogin(), snapshotDirectory: sb.root.appendingPathComponent("shared"))
        return (model, sb, config)
    }

    @Test func addProjectNameDefaultsFromURLUntilEdited() {
        var form = CloneForm()
        form.setURL("https://github.com/x/my-repo.git")
        #expect(form.name == "my-repo")
        form.setName("Custom")
        form.setURL("https://github.com/x/other.git")
        #expect(form.name == "Custom")                 // the user's edit wins
    }

    @Test func cloneFormValidation() {
        let sb = Sandbox(); try? FileManager.default.createDirectory(at: sb.scanRoot, withIntermediateDirectories: true)
        var form = CloneForm()
        #expect(!form.canSubmit(in: sb.scanRoot))
        form.setURL("https://github.com/x/y.git")
        #expect(form.canSubmit(in: sb.scanRoot))
        form.setURL("--upload-pack=evil")
        #expect(!form.canSubmit(in: sb.scanRoot) && form.problem(in: sb.scanRoot) != nil)
        form.setURL("https://github.com/x/y.git"); form.setName("a/b")
        #expect(!form.canSubmit(in: sb.scanRoot))
    }

    @Test func addProjectDisabledUntilNameValid() throws {
        let sb = Sandbox(); try FileManager.default.createDirectory(at: sb.scanRoot.appendingPathComponent("taken"), withIntermediateDirectories: true)
        var form = NewFolderForm()
        #expect(!form.canSubmit(in: sb.scanRoot))
        form.name = "taken"
        #expect(!form.canSubmit(in: sb.scanRoot) && form.problem(in: sb.scanRoot) == "A folder with that name already exists here.")
        form.name = "Fresh"
        #expect(form.canSubmit(in: sb.scanRoot) && form.problem(in: sb.scanRoot) == nil)
    }

    @Test func savingGitIdentityWritesGlobalConfig() async throws {
        let (model, sb, _) = modelWithTempGlobalGit(); defer { _ = sb }
        try await model.saveGitIdentity(name: "David N", email: "d@nexventures.net")
        let snap = await model.loadGitSettings()
        #expect(snap.name == "David N" && snap.email == "d@nexventures.net")
        #expect(model.gitIdentitySet)
    }

    @Test func defaultBranchSettingWritesGitConfig() async throws {
        let (model, sb, _) = modelWithTempGlobalGit(); defer { _ = sb }
        try await model.saveDefaultBranch("trunk")
        #expect(model.settings.settings.defaultBranch == "trunk")
        #expect((await model.loadGitSettings()).defaultBranch == "trunk")
    }

    @Test func invalidDefaultBranchIsRejected() async {
        let (model, sb, _) = modelWithTempGlobalGit(); defer { _ = sb }
        await #expect(throws: ProjectCreationError.invalidBranch) { try await model.saveDefaultBranch("--bad") }
        #expect(model.settings.settings.defaultBranch == "main")
    }

    @Test func pullPreferenceMapsToStrategy() {
        #expect(PullPreference.ffOnly.strategy == .ffOnly)
        #expect(PullPreference.merge.strategy == .merge)
        #expect(PullPreference.rebase.strategy == .rebase)
    }

    @Test func avatarPaletteIsValid() {
        #expect(AvatarPalette.hexes.count >= 6)
        for hex in AvatarPalette.hexes { #expect(hex.hasPrefix("#") && hex.count == 7) }
    }

    @Test func appearanceChoicesCoverAllModes() {
        #expect(Set(AppearanceMode.allCases) == [.system, .light, .dark])
    }

    @Test func defaultBranchAdoptsGitsGlobalValue() async throws {
        let (model, sb, config) = modelWithTempGlobalGit(); defer { _ = sb }
        try "[init]\n\tdefaultBranch = master\n".write(to: config, atomically: true, encoding: .utf8)
        #expect(model.settings.settings.defaultBranch == "main")
        await model.refreshGitIdentity()
        #expect(model.settings.settings.defaultBranch == "master")
    }
}
