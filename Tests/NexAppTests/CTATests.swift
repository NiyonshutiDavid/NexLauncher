import Testing
import Foundation
import NexCore
@testable import NexApp
import NexTestSupport

@Suite struct CTATests {
    private func ctx(identity: Bool = false, changes: Int = 0, lastRun: String? = nil, running: Bool = false,
                     themeChanged: Bool = false, widgets: Bool = false, login: Bool = false) -> CTAContext {
        CTAContext(gitIdentitySet: identity, projectsWithChanges: changes, lastRunName: lastRun, anythingRunning: running,
                   themeChanged: themeChanged, widgetsConfirmed: widgets, launchAtLogin: login)
    }
    private func ids(_ c: CTAContext, dismissed: Set<String> = [], limit: Int = 3) -> [CTAID] {
        CTAEngine.visible(c, dismissed: dismissed, limit: limit).map(\.id)
    }

    @Test func freshUserSeesIdentityAddProjectAndLogin() {
        #expect(ids(ctx()) == [.gitIdentity, .addProject, .login])
    }

    @Test func cappedAtThree() {
        #expect(ids(ctx(changes: 2, lastRun: "X")).count == 3)
        #expect(ids(ctx(changes: 2, lastRun: "X"), limit: 10).count == 7)    // every card applies
    }

    @Test func dismissedCardsAreHidden() {
        #expect(ids(ctx(), dismissed: ["git-identity"]) == [.addProject, .login, .themes])
    }

    @Test func uncommittedNeedsAtLeastOneProject() {
        #expect(!ids(ctx(identity: true, changes: 0), limit: 10).contains(.uncommitted))
        let one = CTAEngine.visible(ctx(identity: true, changes: 1), dismissed: [], limit: 10).first { $0.id == .uncommitted }
        #expect(one?.headline == "1 project has unsaved changes")
        let many = CTAEngine.visible(ctx(identity: true, changes: 4), dismissed: [], limit: 10).first { $0.id == .uncommitted }
        #expect(many?.headline == "4 projects have unsaved changes")
    }

    @Test func resumeOnlyWhenNothingRunningAndHasLastRun() {
        #expect(!ids(ctx(identity: true), dismissed: [], limit: 10).contains(.resume))
        #expect(!ids(ctx(identity: true, lastRun: "CleanPay", running: true), limit: 10).contains(.resume))
        let resume = CTAEngine.visible(ctx(identity: true, lastRun: "CleanPay"), dismissed: [], limit: 10).first { $0.id == .resume }
        #expect(resume?.headline == "Pick up where you left off")
        #expect(resume?.button == "Run CleanPay")
    }

    @Test func themesHiddenOnceChanged() {
        #expect(ids(ctx(), limit: 10).contains(.themes))
        #expect(!ids(ctx(themeChanged: true), limit: 10).contains(.themes))
    }

    @Test func widgetsHiddenOnceConfirmed() {
        #expect(ids(ctx(), limit: 10).contains(.widgets))
        #expect(!ids(ctx(widgets: true), limit: 10).contains(.widgets))
    }

    @Test func loginHiddenWhenEnabled() {
        #expect(!ids(ctx(login: true), limit: 10).contains(.login))
    }

    @Test func orderFollowsPriority() {
        #expect(ids(ctx(changes: 1, lastRun: "X"), limit: 10) == [.gitIdentity, .uncommitted, .resume, .addProject, .login, .themes, .widgets])
    }

    @Test func everyCardHasCopyAndAnIllustration() {
        for cta in CTAEngine.visible(ctx(changes: 2, lastRun: "X"), dismissed: [], limit: 10) {
            #expect(!cta.headline.isEmpty && !cta.body.isEmpty && !cta.button.isEmpty)
        }
        let kinds = CTAEngine.visible(ctx(changes: 2, lastRun: "X"), dismissed: [], limit: 10).map(\.illustration)
        #expect(Set(kinds).count >= 5)
    }
}
