import Testing
import Foundation
import NexCore
import NexProcess
@testable import NexUI

private let prefsOn = NotificationPrefs(enabled: true, ready: true, crash: true, added: true, onlyInBackground: true)

@Suite struct NotificationPlannerTests {
    private let ready = NotificationEvent.serviceReady(project: "CleanPay", projectID: "/p/CleanPay", kind: .frontend, port: 5173)
    private let crashed = NotificationEvent.serviceCrashed(project: "CleanPay", projectID: "/p/CleanPay", kind: .backend, reason: "Exited with code 1: boom")
    private let added = NotificationEvent.projectAdded(name: "Fresh", path: "/p/Fresh", cloned: true)

    @Test func nothingWhenMasterSwitchIsOff() {
        var p = prefsOn; p.enabled = false
        #expect(NotificationPlanner.request(for: ready, prefs: p, appIsActive: false) == nil)
    }

    @Test func readyNotificationNamesProjectAndPort() {
        let r = NotificationPlanner.request(for: ready, prefs: prefsOn, appIsActive: false)
        #expect(r?.title == "CleanPay is ready")
        #expect(r?.body == "Frontend is running on localhost:5173.")
        #expect(r?.projectID == "/p/CleanPay")
        #expect(r?.openURL == "http://localhost:5173")
    }

    @Test func crashNotificationCarriesTheReason() {
        let r = NotificationPlanner.request(for: crashed, prefs: prefsOn, appIsActive: false)
        #expect(r?.title == "CleanPay stopped unexpectedly")
        #expect(r?.body.contains("Backend") == true && r?.body.contains("boom") == true)
        #expect(r?.openURL == nil)
    }

    @Test func addedNotificationDistinguishesCloneFromCreate() {
        #expect(NotificationPlanner.request(for: added, prefs: prefsOn, appIsActive: false)?.title == "Fresh was cloned")
        let created = NotificationEvent.projectAdded(name: "Fresh", path: "/p/Fresh", cloned: false)
        #expect(NotificationPlanner.request(for: created, prefs: prefsOn, appIsActive: false)?.title == "Fresh was created")
    }

    @Test func eachEventHasItsOwnSwitch() {
        var p = prefsOn; p.ready = false
        #expect(NotificationPlanner.request(for: ready, prefs: p, appIsActive: false) == nil)
        #expect(NotificationPlanner.request(for: crashed, prefs: p, appIsActive: false) != nil)
        p = prefsOn; p.crash = false
        #expect(NotificationPlanner.request(for: crashed, prefs: p, appIsActive: false) == nil)
        p = prefsOn; p.added = false
        #expect(NotificationPlanner.request(for: added, prefs: p, appIsActive: false) == nil)
    }

    @Test func staysQuietWhileTheAppIsInFrontWhenAskedTo() {
        #expect(NotificationPlanner.request(for: ready, prefs: prefsOn, appIsActive: true) == nil)
        var p = prefsOn; p.onlyInBackground = false
        #expect(NotificationPlanner.request(for: ready, prefs: p, appIsActive: true) != nil)
    }

    @Test func eventsFromStateTransitions() {
        let id = ServiceID(projectID: "/p/A", kind: .frontend, directory: "/p/A")
        let proj = Project(id: "/p/A", name: "A", root: URL(fileURLWithPath: "/p/A"), targets: [])
        func events(_ before: ServiceState?, _ after: ServiceState) -> [NotificationEvent] {
            NotificationPlanner.events(previous: before.map { [id: $0] } ?? [:], current: [id: after], projects: [proj])
        }
        #expect(events(.starting, .running(port: nil)).isEmpty)
        #expect(events(.running(port: nil), .running(port: 3000)) == [.serviceReady(project: "A", projectID: "/p/A", kind: .frontend, port: 3000)])
        #expect(events(.running(port: 3000), .running(port: 3000)).isEmpty)                      // no repeat
        #expect(events(.running(port: 3000), .failed("Exited with code 2")) == [.serviceCrashed(project: "A", projectID: "/p/A", kind: .frontend, reason: "Exited with code 2")])
        #expect(events(.starting, .failed("Could not start")).count == 1)
        #expect(events(.failed("x"), .failed("x")).isEmpty)                                       // already failed
        #expect(events(.running(port: 3000), .stopped).isEmpty)                                   // a normal stop is silent
        let unknown = NotificationPlanner.events(previous: [:], current: [ServiceID(projectID: "/other", kind: .backend, directory: "/other"): .failed("x")], projects: [proj])
        #expect(unknown.isEmpty)
    }
}

@MainActor
@Suite(.serialized) struct NotificationModelTests {
    private func waitUntil(_ timeout: TimeInterval = 5, _ cond: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if cond() { return true }; try? await Task.sleep(for: .milliseconds(25)) }
        return cond()
    }

    private func siteModel(_ sb: Sandbox, command: String) async -> (AppModel, Project) {
        sb.write("Site/package.json", Sandbox.vite)
        try! FileManager.default.createDirectory(at: sb.scanRoot.appendingPathComponent("Site/node_modules"), withIntermediateDirectories: true)
        let model = sb.makeModel(); model.reloadWidgets = {}
        await model.refresh()
        let t = model.projects[0].targets[0]
        model.overrides.set(Override(command: command), forPath: OverrideStore.key(directory: t.directory, kind: t.kind))
        await model.refresh()
        return (model, model.projects[0])
    }

    @Test func enablingAsksForPermissionAndKeepsTheSwitchOffIfDenied() async {
        let sb = Sandbox()
        let model = sb.makeModel()
        sb.notifier.grantOnRequest = false
        await model.setNotificationsEnabled(true)
        #expect(!model.settings.settings.notificationsEnabled)
        #expect(model.notificationStatus == .denied)
        sb.notifier.grantOnRequest = true
        sb.notifier.status = .notDetermined
        await model.setNotificationsEnabled(true)
        #expect(model.settings.settings.notificationsEnabled && model.notificationStatus == .authorized)
        await model.setNotificationsEnabled(false)
        #expect(!model.settings.settings.notificationsEnabled)
    }

    @Test func aServiceBecomingReadyPostsANotification() async {
        let sb = Sandbox(); defer { _ = sb }
        let (model, project) = await siteModel(sb, command: "echo 'http://localhost:4567'; sleep 30")
        model.settings.settings.notificationsEnabled = true
        await model.run(project, kinds: [.frontend])
        #expect(await waitUntil { sb.notifier.posted.contains { $0.title == "Site is ready" } })
        #expect(sb.notifier.posted.first?.openURL == "http://localhost:4567")
        await model.stopAllServices()
    }

    @Test func aCrashPostsButAUserStopDoesNot() async {
        let sb = Sandbox(); defer { _ = sb }
        let (model, project) = await siteModel(sb, command: "echo boom; exit 3")
        model.settings.settings.notificationsEnabled = true
        await model.run(project, kinds: [.frontend])
        #expect(await waitUntil { sb.notifier.posted.contains { $0.title == "Site stopped unexpectedly" } })
        let before = sb.notifier.posted.count

        let sb2 = Sandbox(); defer { _ = sb2 }
        let (quiet, quietProject) = await siteModel(sb2, command: "sleep 30")
        quiet.settings.settings.notificationsEnabled = true
        await quiet.run(quietProject, kinds: [.frontend])
        #expect(await waitUntil { quiet.isRunning(quietProject) })
        await quiet.stop(quietProject)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(sb2.notifier.posted.isEmpty)
        #expect(before >= 1)
    }

    @Test func noNotificationsWhileDisabledOrAppIsActive() async {
        let sb = Sandbox(); defer { _ = sb }
        let (model, project) = await siteModel(sb, command: "echo 'http://localhost:4000'; sleep 30")
        await model.run(project, kinds: [.frontend])                      // master switch off
        #expect(await waitUntil { model.processes.states.values.contains(.running(port: 4000)) })
        try? await Task.sleep(for: .milliseconds(200))
        #expect(sb.notifier.posted.isEmpty)
        await model.stopAllServices()
    }

    @Test func creatingAProjectPostsAnAddedNotification() async throws {
        let sb = Sandbox()
        try FileManager.default.createDirectory(at: sb.scanRoot, withIntermediateDirectories: true)
        let model = sb.makeModel(); model.reloadWidgets = {}
        model.settings.settings.notificationsEnabled = true
        _ = try await model.createProject(name: "Fresh", in: sb.scanRoot, initGit: false)
        #expect(await waitUntil { sb.notifier.posted.contains { $0.title == "Fresh was created" } })
    }

    @Test func testNotificationUsesTheNotifierRegardlessOfPrefs() async {
        let sb = Sandbox()
        let model = sb.makeModel()
        await model.sendTestNotification()
        #expect(sb.notifier.posted.first?.title == "NexLauncher notifications work")
    }

    @Test func openingFromANotificationShowsTheProject() async {
        let sb = Sandbox(); defer { _ = sb }
        let (model, project) = await siteModel(sb, command: "sleep 30")
        model.openFromNotification(projectID: project.id)
        #expect(model.page == .project(project.id))
        model.openFromNotification(projectID: "/gone")
        #expect(model.page == .project(project.id))             // unknown ids are ignored
    }
}
