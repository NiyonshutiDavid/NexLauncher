import Testing
import Foundation
import NexCore
import NexGit
import NexTestSupport
@testable import NexUI

@MainActor
@Suite(.serialized) struct AppModelV2Tests {
    private let flutter = "name: a\ndependencies:\n  flutter:\n    sdk: flutter\n"

    private func waitUntil(_ timeout: TimeInterval = 5, _ cond: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if cond() { return true }; try? await Task.sleep(for: .milliseconds(25)) }
        return cond()
    }

    private func siteModel(_ sb: Sandbox, command: String = "sleep 30") async -> (AppModel, Project) {
        sb.write("Site/package.json", Sandbox.vite)
        try! FileManager.default.createDirectory(at: sb.scanRoot.appendingPathComponent("Site/node_modules"), withIntermediateDirectories: true)
        let model = sb.makeModel(); model.reloadWidgets = {}
        await model.refresh()
        let t = model.projects[0].targets[0]
        model.overrides.set(Override(command: command), forPath: OverrideStore.key(directory: t.directory, kind: t.kind))
        await model.refresh()
        return (model, model.projects[0])
    }

    @Test func refreshBuildsTreeAndFlatProjects() async {
        let sb = Sandbox()
        sb.write("intern/a/pubspec.yaml", flutter); sb.write("intern/b/pubspec.yaml", flutter)
        sb.write("Site/package.json", Sandbox.vite)
        let model = sb.makeModel(); model.reloadWidgets = {}
        await model.refresh()
        #expect(model.tree.count == 2)
        #expect(model.tree.first { $0.name == "intern" }?.kind == .collection)
        #expect(model.projects.count == 3)
    }

    @Test func viewModePersistsToSettingsFile() {
        let sb = Sandbox()
        let model = sb.makeModel()
        #expect(model.viewMode == .cards)
        model.viewMode = .folders
        #expect(SettingsStore(fileURL: sb.root.appendingPathComponent("settings.json")).settings.viewMode == .folders)
    }

    @Test func runRecordsLastRun() async {
        let sb = Sandbox(); defer { _ = sb }
        let (model, p) = await siteModel(sb)
        await model.run(p, kinds: [.frontend])
        #expect(model.settings.settings.lastRun == LastRun(projectID: p.id, action: "Frontend"))
        #expect(SettingsStore(fileURL: sb.root.appendingPathComponent("settings.json")).settings.lastRun?.action == "Frontend")
        await model.stopAllServices()
    }

    @Test func dismissingCTAPersistsAndHidesIt() {
        let sb = Sandbox()
        let model = sb.makeModel()
        model.gitIdentitySet = false
        #expect(model.visibleCTAs.map(\.id).contains(.gitIdentity))
        model.dismiss(.gitIdentity)
        #expect(!model.visibleCTAs.map(\.id).contains(.gitIdentity))
        #expect(SettingsStore(fileURL: sb.root.appendingPathComponent("settings.json")).settings.dismissedCTAs.contains("git-identity"))
    }

    @Test func resetTipsClearsDismissals() {
        let model = Sandbox().makeModel()
        model.dismiss(.addProject); model.dismiss(.login)
        model.resetTips()
        #expect(model.settings.settings.dismissedCTAs.isEmpty)
    }

    @Test func performAddProjectOpensSheet() async {
        let model = Sandbox().makeModel()
        await model.perform(.addProject)
        #expect(model.sheet == .addProject(.newFolder))
    }

    @Test func performGitIdentityGoesToGitSettings() async {
        let model = Sandbox().makeModel()
        await model.perform(.gitIdentity)
        #expect(model.page == .settings(.git))
    }

    @Test func performThemesGoesToAppearance() async {
        let model = Sandbox().makeModel()
        await model.perform(.themes)
        #expect(model.page == .settings(.appearance))
    }

    @Test func performWidgetsOpensHowTo() async {
        let model = Sandbox().makeModel()
        await model.perform(.widgets)
        #expect(model.sheet == .widgetsHowTo)
    }

    @Test func performLoginEnablesLaunchAtLogin() async {
        let model = Sandbox().makeModel()
        #expect(!model.login.isEnabled)
        await model.perform(.login)
        #expect(model.login.isEnabled)
    }

    @Test func performUncommittedFiltersProjects() async {
        let sb = Sandbox()
        sb.write("Dirty/package.json", Sandbox.vite)
        sb.write("Clean/package.json", Sandbox.vite)
        TempRepo(initialize: false).run(["init", "-b", "main"], in: sb.scanRoot.appendingPathComponent("Dirty"))
        let model = sb.makeModel(); model.reloadWidgets = {}
        await model.refresh()
        await model.refreshGitBadges()
        await model.perform(.uncommitted)
        #expect(model.filteredProjects.map(\.name) == ["Dirty"])
        #expect(model.page == .home)
    }

    @Test func performResumeRunsLastRun() async {
        let sb = Sandbox(); defer { _ = sb }
        let (model, p) = await siteModel(sb)
        model.settings.settings.lastRun = LastRun(projectID: p.id, action: "Frontend")
        await model.perform(.resume)
        #expect(await waitUntil { model.isRunning(p) })
        await model.stopAllServices()
    }

    @Test func ctaContextReflectsState() async {
        let sb = Sandbox(); defer { _ = sb }
        let (model, p) = await siteModel(sb)
        model.settings.settings.lastRun = LastRun(projectID: p.id, action: "Frontend")
        model.gitIdentitySet = true
        let c = model.ctaContext
        #expect(c.lastRunName == "Site" && c.gitIdentitySet && !c.anythingRunning && !c.themeChanged)
        model.settings.settings.theme = .ocean
        #expect(model.ctaContext.themeChanged)
    }

    @Test func openTerminalCreatesTabAtDirectory() async {
        let sb = Sandbox()
        sb.write("Site/package.json", Sandbox.vite)
        let model = sb.makeModel()
        let dir = sb.scanRoot.appendingPathComponent("Site")
        model.openTerminal(at: dir)
        #expect(model.terminals.sessions.count == 1)
        #expect(model.terminals.sessions[0].directory == dir)
        model.terminals.closeAll()
    }

    @Test func addProjectCreatesFolderRefreshesAndOpensIt() async throws {
        let sb = Sandbox()
        try FileManager.default.createDirectory(at: sb.scanRoot, withIntermediateDirectories: true)
        let model = sb.makeModel(); model.reloadWidgets = {}
        let url = try await model.createProject(name: "Fresh App", in: sb.scanRoot, initGit: true)
        #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path))
        #expect(model.page == .folder(url.path))
    }

    @Test func runActionFromKinds() {
        #expect(RunAction.from(kinds: [.frontend, .backend]) == .both)
        #expect(RunAction.from(kinds: [.frontend]) == .frontend)
        #expect(RunAction.from(kinds: [.flutter]) == .flutter)
    }
}
