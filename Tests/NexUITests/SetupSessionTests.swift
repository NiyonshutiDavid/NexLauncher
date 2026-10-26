import Testing
import Foundation
import NexCore
@testable import NexUI

@MainActor
@Suite(.serialized) struct SetupSessionTests {
    private func waitUntil(_ timeout: TimeInterval = 10, _ cond: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if cond() { return true }; try? await Task.sleep(for: .milliseconds(25)) }
        return cond()
    }

    private func site(_ sb: Sandbox, lock: String? = nil) async -> AppModel {
        sb.write("Site/package.json", #"{"scripts":{"dev":"sleep 30"},"devDependencies":{"vite":"5"}}"#)
        if let lock { sb.write("Site/\(lock)", "") }
        let m = sb.makeModel(); m.reloadWidgets = {}
        await m.refresh()
        return m
    }

    @Test func runningWithoutDependenciesOpensASetupSessionWithReadableSteps() async {
        let sb = Sandbox(); defer { _ = sb }
        let m = await site(sb, lock: "pnpm-lock.yaml")
        await m.run(m.projects[0], kinds: [.frontend])
        let session = m.setup
        #expect(session?.phase == .confirm)
        #expect(session?.steps.count == 1)
        #expect(session?.steps.first?.title == "Install packages with pnpm")
        #expect(session?.steps.first?.command == "pnpm install")
        #expect(session?.steps.first?.status == .pending)
    }

    @Test func stepTitlesDescribeEachStack() {
        #expect(SetupStep.describe("npm install") == "Install packages with npm")
        #expect(SetupStep.describe("python3 -m venv .venv && .venv/bin/python -m pip install -r requirements.txt") == "Create a Python environment and install requirements")
        #expect(SetupStep.describe("composer install") == "Install Composer packages")
        #expect(SetupStep.describe("flutter pub get") == "Get Flutter packages")
        #expect(SetupStep.describe("uv sync") == "Sync the Python environment with uv")
        #expect(SetupStep.describe("something custom") == "Run something custom")
    }

    @Test func successfulSetupRunsTheProjectAndClosesTheSheet() async {
        let sb = Sandbox(); defer { _ = sb }
        let m = await site(sb)
        m.installCommandOverride = "echo installing; mkdir -p node_modules"
        await m.run(m.projects[0], kinds: [.frontend])
        await m.confirmInstall()
        #expect(m.setup == nil)
        #expect(await waitUntil { m.processes.runningCount == 1 })
        await m.stopAllServices()
    }

    @Test func failedSetupKeepsTheSheetOpenWithTheReason() async {
        let sb = Sandbox(); defer { _ = sb }
        let m = await site(sb)
        m.installCommandOverride = "echo registry unreachable; exit 2"
        await m.run(m.projects[0], kinds: [.frontend])
        await m.confirmInstall()
        guard case .failed(let reason)? = m.setup?.phase else { Issue.record("expected failed, got \(String(describing: m.setup?.phase))"); return }
        #expect(reason.contains("registry unreachable"))
        #expect(m.setup?.steps.first?.status == .failed)
        #expect(m.processes.runningCount == 0)
        m.cancelInstall()
        #expect(m.setup == nil)
    }

    @Test func stepsShowProgressWhileRunning() async {
        let sb = Sandbox(); defer { _ = sb }
        let m = await site(sb)
        m.installCommandOverride = "echo step-one; sleep 1; mkdir -p node_modules"
        await m.run(m.projects[0], kinds: [.frontend])
        let task = Task { await m.confirmInstall() }
        #expect(await waitUntil { m.setup?.steps.first?.status == .running })
        #expect(m.setup?.phase == .running)
        #expect(await waitUntil { m.setupLastLine?.contains("step-one") == true })
        await task.value
        await m.stopAllServices()
    }
}

@MainActor
@Suite(.serialized) struct SetupConcurrencyTests {
    @Test func aSecondSetupWaitsUntilTheFirstFinishes() async {
        let sb = Sandbox(); defer { _ = sb }
        sb.write("A/package.json", #"{"scripts":{"dev":"sleep 30"},"devDependencies":{"vite":"5"}}"#)
        sb.write("B/package.json", #"{"scripts":{"dev":"sleep 30"},"devDependencies":{"vite":"5"}}"#)
        let m = sb.makeModel(); m.reloadWidgets = {}
        await m.refresh()
        let a = m.projects.first { $0.name == "A" }!, b = m.projects.first { $0.name == "B" }!
        m.installCommandOverride = "sleep 1; mkdir -p node_modules"
        await m.run(a, kinds: [.frontend])
        let first = Task { await m.confirmInstall() }
        let end = Date().addingTimeInterval(5)
        while m.setup?.phase != .running && Date() < end { try? await Task.sleep(for: .milliseconds(20)) }
        await m.run(b, kinds: [.frontend])                 // refused while A is installing
        #expect(m.setup?.project.id == a.id)
        #expect(m.statusMessage?.text.contains("A") == true)
        await first.value
        await m.stopAllServices()
    }
}
