import Foundation
import NexCore
import NexProcess

public enum RunAction: String, Hashable, Sendable {
    case frontend = "Frontend", backend = "Backend", both = "Both", app = "App", flutter = "Flutter", docker = "Docker"

    /// The action that corresponds to a set of kinds (used to remember the last run).
    public static func from(kinds: Set<ServiceKind>) -> RunAction {
        if kinds.contains(.frontend) && kinds.contains(.backend) { return .both }
        if kinds.contains(.frontend) { return .frontend }
        if kinds.contains(.backend) { return .backend }
        if kinds.contains(.app) { return .app }
        if kinds.contains(.flutter) { return .flutter }
        return .docker
    }

    public var kinds: Set<ServiceKind> {
        switch self {
        case .frontend: return [.frontend]
        case .backend: return [.backend]
        case .both: return [.frontend, .backend]
        case .app: return [.app]
        case .flutter: return [.flutter]
        case .docker: return [.docker]
        }
    }
}

public struct PendingInstall: Equatable {
    public let project: Project
    public let kinds: Set<ServiceKind>
    public let flutterDevice: String?
}

public struct FlutterDevice: Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
}

extension AppModel {
    public func availableActions(for project: Project) -> [RunAction] {
        let kinds = Set(project.targets.map(\.kind))
        var out: [RunAction] = []
        if kinds.contains(.frontend) { out.append(.frontend) }
        if kinds.contains(.backend) { out.append(.backend) }
        if kinds.contains(.frontend) && kinds.contains(.backend) { out.append(.both) }
        if kinds.contains(.app) { out.append(.app) }
        if kinds.contains(.flutter) { out.append(.flutter) }
        if kinds.contains(.docker) { out.append(.docker) }
        return out
    }

    /// Starts the services of `kinds`. If a Node target has no `node_modules`, asks first via `pendingInstall`.
    public func run(_ project: Project, kinds: Set<ServiceKind>, flutterDevice: String? = nil) async {
        let targets = project.targets.filter { kinds.contains($0.kind) }
        if targets.contains(where: CommandBuilder.needsInstall) {
            if let busy = setup, busy.phase == .running, busy.id != project.id {
                statusMessage = StatusMessage(text: "Finish setting up \(busy.project.name) first.", isError: true)
                return
            }
            pendingInstall = PendingInstall(project: project, kinds: kinds, flutterDevice: flutterDevice)
            setup = SetupSession(project: project, steps: targets.filter(CommandBuilder.needsInstall).map { target in
                let body = CommandBuilder.installBody(for: target)
                return SetupStep(id: ProcessManager.id(for: target, projectID: project.id), title: SetupStep.describe(body), command: body)
            })
            showMainWindow()          // the install question lives in the main window
            return
        }
        settings.settings.lastRun = LastRun(projectID: project.id, action: RunAction.from(kinds: kinds).rawValue)
        settings.save()
        for var target in targets {
            if target.kind == .flutter, let device = flutterDevice, target.command.hasPrefix("cd ") {
                target.command = CommandBuilder.command(for: .flutter, at: target.directory, framework: nil, flutterDevice: device)
            }
            processes.start(target, projectID: project.id)
        }
        publishSnapshot()
    }

    public func confirmInstall() async {
        guard let pending = pendingInstall else { return }
        pendingInstall = nil
        setup?.phase = .running
        for target in pending.project.targets where pending.kinds.contains(target.kind) && CommandBuilder.needsInstall(target) {
            var install = target
            install.port = nil        // an install isn't the server: it must not look 'ready' on a configured port
            install.command = installCommandOverride.map { "cd \(CommandBuilder.quote(target.directory.path)) && \($0)" }
                ?? CommandBuilder.installCommand(for: target)
            let id = ProcessManager.id(for: target, projectID: pending.project.id)
            setup?.mark(id, .running)
            processes.start(install, projectID: pending.project.id)
            while processes.states[id]?.isActive == true { try? await Task.sleep(for: .milliseconds(50)) }
            if processes.wasUserStopped(id) { setup = nil; return }          // Stop pressed mid-install: don't start the server
            if case .failed(let reason) = processes.states[id] {               // keep the sheet open with the reason
                setup?.mark(id, .failed)
                setup?.phase = .failed(reason)
                return
            }
            setup?.mark(id, .done)
        }
        // Setup can change how a project runs (e.g. a new .venv), so rescan before starting it.
        await refresh()
        let fresh = project(id: pending.project.id) ?? pending.project
        if setup?.id == pending.project.id { setup = nil }
        await run(fresh, kinds: pending.kinds, flutterDevice: pending.flutterDevice)
    }

    public func cancelInstall() { pendingInstall = nil; setup = nil }

    /// The newest log line of the setup step that is running (for the sheet).
    public var setupLastLine: String? {
        guard let step = setup?.steps.first(where: { $0.status == .running }) else { return nil }
        return processes.logs[step.id]?.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }).map(PortParser.stripANSI)
    }


    public func stop(_ project: Project) async {
        for id in processes.states.keys where id.projectID == project.id && processes.states[id]?.isActive == true {
            await processes.stop(id)
        }
        publishSnapshot()
    }

    public func stopAllServices() async {
        await processes.stopAll()
        publishSnapshot()
    }

    // MARK: - Flutter devices

    public nonisolated static func parseFlutterDevices(_ json: String) -> [FlutterDevice] {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return array.compactMap { d in
            guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
            return FlutterDevice(id: id, name: name)
        }
    }

    public func flutterDevices() async -> [FlutterDevice] {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-lc", "flutter devices --machine"]
            let out = Pipe.closeOnExec()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return [] }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return Self.parseFlutterDevices(String(decoding: data, as: UTF8.self))
        }.value
    }
}
