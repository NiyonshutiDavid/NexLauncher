import Testing
import Foundation
import NexCore
import NexGit
@testable import NexUI

@MainActor
@Suite struct OnboardingTests {
    private func modelWithTempGlobalGit() -> (AppModel, Sandbox, URL) {
        let sb = Sandbox()
        let config = sb.root.appendingPathComponent("gitconfig-global")
        FileManager.default.createFile(atPath: config.path, contents: nil)
        let git = GitService(runner: GitRunner(extraEnvironment: ["GIT_CONFIG_GLOBAL": config.path, "GIT_CONFIG_NOSYSTEM": "1"]))
        let model = AppModel(settings: SettingsStore(fileURL: sb.root.appendingPathComponent("settings.json")),
                             overrides: OverrideStore(fileURL: sb.root.appendingPathComponent("o.json")),
                             git: git, login: FakeLogin(), notifier: sb.notifier, appIsActive: { false },
                             snapshotDirectory: sb.root.appendingPathComponent("shared"))
        model.reloadWidgets = {}
        return (model, sb, config)
    }

    @Test func showsOnlyUntilCompleted() {
        let model = Sandbox().makeModel()
        #expect(model.showOnboarding)
        model.settings.settings.onboardingCompleted = true
        #expect(!model.showOnboarding)
    }

    @Test func stepsAdvanceAndGoBackWithinBounds() throws {
        let sb = Sandbox()
        try FileManager.default.createDirectory(at: sb.scanRoot, withIntermediateDirectories: true)
        let ob = OnboardingModel(model: sb.makeModel())
        #expect(ob.step == .welcome && ob.isFirst && !ob.isLast)
        ob.back(); #expect(ob.step == .welcome)
        for _ in 0..<10 { ob.name = "David"; ob.next() }
        #expect(ob.step == .extras && ob.isLast)
        ob.back(); #expect(ob.step == .ai)
        #expect(OnboardingStep.allCases.count == 7)
    }

    @Test func nameStepNeedsAName() {
        let ob = OnboardingModel(model: Sandbox().makeModel())
        ob.next(); #expect(ob.step == .name)
        ob.name = "   "
        #expect(!ob.canAdvance)
        ob.next(); #expect(ob.step == .name)
        ob.name = "David"
        #expect(ob.canAdvance)
        ob.next(); #expect(ob.step == .projects)
    }

    @Test func projectsStepNeedsAnExistingFolderAndCountsProjects() async throws {
        let sb = Sandbox()
        sb.write("A/package.json", Sandbox.vite); sb.write("B/package.json", Sandbox.vite)
        let ob = OnboardingModel(model: sb.makeModel())
        ob.folder = sb.scanRoot
        await ob.scanFolder()
        #expect(ob.detectedCount == 2 && ob.folderExists)
        ob.folder = sb.root.appendingPathComponent("does-not-exist")
        await ob.scanFolder()
        #expect(ob.detectedCount == nil && !ob.folderExists)
        ob.step = .projects
        #expect(!ob.canAdvance)
    }

    @Test func finishAppliesEverythingAndMarksCompleted() async throws {
        let (model, sb, _) = modelWithTempGlobalGit(); defer { _ = sb }
        sb.write("Site/package.json", Sandbox.vite)
        let ob = OnboardingModel(model: model)
        ob.name = "Dave"
        ob.folder = sb.scanRoot
        ob.gitName = "Dave N"; ob.gitEmail = "dave@nexventures.net"
        ob.theme = .forest; ob.appearance = .dark
        ob.notifications = true; ob.launchAtLogin = true
        ob.defaultAgent = .codex; ob.autonomy = .plan
        await ob.finish()
        let s = model.settings.settings
        #expect(s.displayName == "Dave" && s.scanRoot == sb.scanRoot)
        #expect(s.theme == .forest && s.appearance == .dark)
        #expect(s.notificationsEnabled && s.onboardingCompleted)
        #expect(model.login.isEnabled)
        #expect(s.defaultAgent == .codex && s.agentAutonomy == .plan)
        let snap = await model.loadGitSettings()
        #expect(snap.name == "Dave N" && snap.email == "dave@nexventures.net")
        #expect(model.projects.map(\.name) == ["Site"])                // rescanned
        #expect(!model.showOnboarding)
    }

    @Test func blankGitFieldsAreLeftAlone() async {
        let (model, sb, _) = modelWithTempGlobalGit(); defer { _ = sb }
        let ob = OnboardingModel(model: model)
        ob.name = "Dave"
        await ob.finish()
        let snap = await model.loadGitSettings()
        #expect(snap.name == nil && snap.email == nil)
        #expect(!model.settings.settings.notificationsEnabled && !model.login.isEnabled)
    }

    @Test func skippingOnlyMarksOnboardingDone() async {
        let model = Sandbox().makeModel()
        let before = model.settings.settings
        model.skipOnboarding()
        var after = model.settings.settings
        #expect(after.onboardingCompleted)
        after.onboardingCompleted = false
        #expect(after == before)
    }

    @Test func settingsCanReplayTheWelcome() {
        let model = Sandbox().makeModel()
        model.skipOnboarding()
        model.replayOnboarding()
        #expect(model.showOnboarding)
    }

    @Test func prefillsFromCurrentSettingsAndGlobalGit() async throws {
        let (model, sb, _) = modelWithTempGlobalGit(); defer { _ = sb }
        try await model.saveGitIdentity(name: "Existing", email: "e@x.com")
        model.settings.settings.displayName = "Pre"
        let ob = OnboardingModel(model: model)
        await ob.loadExisting()
        #expect(ob.name == "Pre" && ob.gitName == "Existing" && ob.gitEmail == "e@x.com")
    }
}
