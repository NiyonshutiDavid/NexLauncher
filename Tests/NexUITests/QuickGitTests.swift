import Testing
import Foundation
import NexCore
import NexGit
import NexTestSupport
@testable import NexUI

@MainActor
@Suite struct QuickGitTests {
    /// A sandbox whose "Site" project is a real git repo with an origin, plus a collaborator clone.
    private func setup() async -> (Sandbox, AppModel, Project, TempRepo, URL) {
        let sb = Sandbox()
        sb.write("Site/package.json", Sandbox.vite)
        let siteDir = sb.scanRoot.appendingPathComponent("Site")
        let helper = TempRepo(initialize: false)
        helper.run(["init", "-b", "main"], in: siteDir)
        helper.run(["config", "user.name", "T"], in: siteDir); helper.run(["config", "user.email", "t@x.com"], in: siteDir)
        helper.run(["config", "commit.gpgsign", "false"], in: siteDir)
        helper.run(["add", "-A"], in: siteDir); helper.run(["commit", "-m", "first"], in: siteDir)
        let bare = helper.base.appendingPathComponent("origin.git")
        try! FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        helper.run(["init", "--bare", "-b", "main"], in: bare)
        helper.run(["remote", "add", "origin", bare.path], in: siteDir)
        helper.run(["push", "-u", "origin", "main"], in: siteDir)
        let model = sb.makeModel(); model.reloadWidgets = {}
        await model.refresh()
        return (sb, model, model.projects[0], helper, bare)
    }

    @Test func pushSendsLocalCommitsToTheRemote() async {
        let (sb, m, p, helper, bare) = await setup(); defer { _ = sb; _ = helper }
        try! "more".write(to: p.root.appendingPathComponent("extra.txt"), atomically: true, encoding: .utf8)
        helper.run(["add", "-A"], in: p.root); helper.run(["commit", "-m", "second"], in: p.root)
        let report = await m.quickGit(.push, project: p)
        #expect(report.success)
        #expect(helper.run(["log", "--format=%s"], in: bare).contains("second"))
        #expect(m.statusMessage?.isError == false)
    }

    @Test func pullBringsInRemoteCommits() async {
        let (sb, m, p, helper, bare) = await setup(); defer { _ = sb }
        let collab = helper.base.appendingPathComponent("collab")
        helper.run(["clone", bare.path, "collab"], in: helper.base)
        helper.run(["config", "user.name", "C"], in: collab); helper.run(["config", "user.email", "c@x.com"], in: collab)
        helper.run(["config", "commit.gpgsign", "false"], in: collab)
        try! "from collab".write(to: collab.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)
        helper.run(["add", "-A"], in: collab); helper.run(["commit", "-m", "remote"], in: collab); helper.run(["push"], in: collab)
        let report = await m.quickGit(.pull, project: p)
        #expect(report.success)
        #expect(FileManager.default.fileExists(atPath: p.root.appendingPathComponent("c.txt").path))
    }

    @Test func fetchReportsSuccess() async {
        let (sb, m, p, helper, _) = await setup(); defer { _ = sb; _ = helper }
        let report = await m.quickGit(.fetch, project: p)
        #expect(report.success && report.message.contains("Site"))
    }

    @Test func failureNamesTheProjectAndMarksTheMessageAsAnError() async {
        let sb = Sandbox(); defer { _ = sb }
        sb.write("Plain/package.json", Sandbox.vite)
        let helper = TempRepo(initialize: false)
        helper.run(["init", "-b", "main"], in: sb.scanRoot.appendingPathComponent("Plain"))      // repo without a remote
        let m = sb.makeModel(); m.reloadWidgets = {}
        await m.refresh()
        let report = await m.quickGit(.pull, project: m.projects[0])
        #expect(!report.success && report.message.contains("Plain"))
        #expect(m.statusMessage?.isError == true)
    }

    @Test func projectWithoutARepositoryIsReportedPlainly() async {
        let sb = Sandbox(); defer { _ = sb }
        sb.write("NoGit/package.json", Sandbox.vite)
        let m = sb.makeModel(); m.reloadWidgets = {}
        await m.refresh()
        let report = await m.quickGit(.push, project: m.projects[0])
        #expect(!report.success && report.message == "NoGit isn't a git repository.")
    }

    @Test func statusMessageIsDismissible() async {
        let (sb, m, p, helper, _) = await setup(); defer { _ = sb; _ = helper }
        _ = await m.quickGit(.fetch, project: p)
        #expect(m.statusMessage != nil)
        m.dismissStatusMessage()
        #expect(m.statusMessage == nil)
    }

    @Test func menuBarSearchMatchesNamesCaseInsensitively() async {
        let (sb, m, _, helper, _) = await setup(); defer { _ = sb; _ = helper }
        #expect(MenuBarFilter.matching("sIT", in: m.projects).map(\.name) == ["Site"])
        #expect(MenuBarFilter.matching("  ", in: m.projects).count == 1)
        #expect(MenuBarFilter.matching("zzz", in: m.projects).isEmpty)
    }

    @Test func runningProjectsListIncludesPortsForTheMenuBar() async {
        let sb = Sandbox(); defer { _ = sb }
        sb.write("Site/package.json", Sandbox.vite)
        try! FileManager.default.createDirectory(at: sb.scanRoot.appendingPathComponent("Site/node_modules"), withIntermediateDirectories: true)
        let m = sb.makeModel(); m.reloadWidgets = {}
        await m.refresh()
        let t = m.projects[0].targets[0]
        m.overrides.set(Override(command: "echo 'http://localhost:6100'; sleep 30"), forPath: OverrideStore.key(directory: t.directory, kind: t.kind))
        await m.refresh()
        await m.run(m.projects[0], kinds: [.frontend])
        let end = Date().addingTimeInterval(5)
        while m.runningPorts(for: m.projects[0]).isEmpty && Date() < end { try? await Task.sleep(for: .milliseconds(25)) }
        #expect(m.runningPorts(for: m.projects[0]) == [6100])
        #expect(m.runningProjects.map(\.name) == ["Site"])
        await m.stopAllServices()
    }
}
