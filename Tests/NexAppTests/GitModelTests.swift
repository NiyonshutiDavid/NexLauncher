import Testing
import Foundation
import NexGit
import NexTestSupport
@testable import NexApp

@MainActor
@Suite struct GitModelTests {
    private func model(_ r: TempRepo) -> GitModel { GitModel(repo: r.dir, service: r.service) }

    @Test func reloadPopulatesStatusBranchesAndHistory() async {
        let r = TempRepo()
        r.write("a.txt", "a"); r.commitAll("first")
        r.write("b.txt", "b")
        let m = model(r)
        await m.reload()
        #expect(m.status?.branch == "main")
        #expect(m.status?.changes.count == 1)
        #expect(m.branches == ["main"])
        #expect(m.history.map(\.subject) == ["first"])
        #expect(!m.needsIdentity)
    }

    @Test func commitClearsFieldsAndRefreshes() async {
        let r = TempRepo()
        r.write("a.txt", "a")
        let m = model(r)
        await m.reload()
        await m.toggleStage(m.status!.changes[0])
        m.summary = "add a"; m.descriptionText = "details"
        await m.commit()
        #expect(m.summary.isEmpty && m.descriptionText.isEmpty)
        #expect(m.status?.changes.isEmpty == true)
        #expect(m.history.first?.subject == "add a")
        #expect(m.errorMessage == nil)
    }

    @Test func commitStagesEverythingWhenNothingIsStaged() async {
        let r = TempRepo()
        r.write("a.txt", "a"); r.write("b.txt", "b")
        let m = model(r)
        await m.reload()
        m.summary = "both"
        await m.commit()
        #expect(m.status?.changes.isEmpty == true)
        #expect(m.history.count == 1)
    }

    @Test func commitWithEmptySummarySetsErrorMessage() async {
        let r = TempRepo()
        r.write("a.txt", "a")
        let m = model(r)
        await m.reload()
        await m.commit()
        #expect(m.errorMessage == GitError.emptyMessage.errorDescription)
        #expect(m.status?.changes.first?.isStaged == false)
    }

    @Test func pullNonFastForwardOffersMergeChoice() async {
        let r = TempRepo()
        r.write("a.txt", "a"); r.commitAll()
        let bare = r.attachBareRemote()
        r.git("push", "-u", "origin", "main")
        let collab = r.collaboratorClone(of: bare)
        r.write("c.txt", "c", in: collab); r.commitAll("remote", in: collab); r.run(["push"], in: collab)
        r.write("b.txt", "b"); r.commitAll("local")
        let m = model(r)
        await m.reload()
        await m.pull(strategy: .ffOnly)
        #expect(m.pendingPullChoice)
        #expect(m.errorMessage != nil)
        await m.pull(strategy: .merge)
        #expect(!m.pendingPullChoice)
        #expect(m.errorMessage == nil)
        #expect(FileManager.default.fileExists(atPath: r.dir.appendingPathComponent("c.txt").path))
    }

    @Test func pushErrorSurfacesGitMessage() async {
        let r = TempRepo()
        r.write("a.txt", "a"); r.commitAll()
        let m = model(r)
        await m.reload()
        await m.push()
        #expect(m.errorMessage?.isEmpty == false)
    }

    @Test func pushSucceedsAndUpdatesAheadCount() async {
        let r = TempRepo()
        r.write("a.txt", "a"); r.commitAll()
        r.attachBareRemote()
        let m = model(r)
        await m.reload()
        await m.push()
        #expect(m.errorMessage == nil)
        #expect(m.status?.upstream == "origin/main")
    }

    @Test func firstRunPromptsWhenIdentityMissing() async {
        let r = TempRepo(identity: false)
        let m = model(r)
        await m.reload()
        #expect(m.needsIdentity)
        await m.saveIdentity(GitIdentity(name: "David", email: "d@x.com"), scope: .repo)
        #expect(!m.needsIdentity)
        #expect(m.identity.name == "David")
    }

    @Test func selectingFileLoadsItsDiff() async {
        let r = TempRepo()
        r.write("a.txt", "one\n"); r.commitAll()
        r.write("a.txt", "two\n")
        let m = model(r)
        await m.reload()
        await m.select(m.status!.changes[0])
        #expect(m.diffText.contains("+two"))
    }

    @Test func notARepoSetsErrorWithoutCrashing() async {
        let r = TempRepo(initialize: false)
        let m = model(r)
        await m.reload()
        #expect(m.status == nil)
        #expect(m.errorMessage != nil)
    }
}

@MainActor
@Suite struct GitBadgeTests {
    @Test func badgeSummarisesChangesAcrossRepos() async {
        let sb = Sandbox()
        sb.write("Proj/package.json", Sandbox.vite)
        let proj = sb.scanRoot.appendingPathComponent("Proj")
        TempRepo(initialize: false).run(["init", "-b", "main"], in: proj)
        sb.write("Proj/new.txt", "x")
        let model = sb.makeModel()
        await model.refresh()
        await model.refreshGitBadges()
        #expect(model.gitBadges[model.projects[0].id]?.changes == 2)   // package.json + new.txt
        #expect(model.gitBadges[model.projects[0].id]?.repoCount == 1)
    }

    @Test func projectWithoutRepoHasNoBadge() async {
        let sb = Sandbox()
        sb.write("Plain/package.json", Sandbox.vite)
        let model = sb.makeModel()
        await model.refresh()
        await model.refreshGitBadges()
        #expect(model.gitBadges[model.projects[0].id] == nil)
    }
}
