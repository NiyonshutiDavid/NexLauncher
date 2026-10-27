import Foundation
import Observation
import NexCore

/// Runs device tools. A protocol so tests can check the exact commands.
public protocol DeviceShell: Sendable {
    func output(_ args: [String]) async -> String?
    func launchDetached(_ args: [String])
}

/// Runs device and agent tools directly, or on the host inside a Flatpak (where they're installed).
public struct SystemDeviceShell: DeviceShell {
    let flatpak: Bool
    public init(flatpak: Bool = Platform.isFlatpak) { self.flatpak = flatpak }

    public func invocation(_ args: [String]) -> HostInvocation { HostCommand.argv(args, flatpak: flatpak) }

    public func output(_ args: [String]) async -> String? {
        let inv = invocation(args)
        return await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: inv.executable)
            p.arguments = inv.arguments
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return nil }
            let timer = DispatchWorkItem { if p.isRunning { p.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: timer)
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            timer.cancel()
            return String(decoding: data, as: UTF8.self)
        }.value
    }

    /// Starts something that keeps running on its own (an emulator window).
    public func launchDetached(_ args: [String]) {
        let inv = invocation(args)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: inv.executable)
        p.arguments = inv.arguments
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        try? p.run()
    }
}

/// iOS simulators, Android emulators from Android Studio, and devices Flutter can run on.
@MainActor @Observable
public final class DevicesModel {
    public private(set) var simulators: [SimulatorDevice] = []
    public private(set) var avds: [String] = []
    public private(set) var connected: [FlutterDevice] = []
    public private(set) var isLoading = false
    public private(set) var busy: Set<String> = []
    private let shell: DeviceShell
    private let androidSDK: URL?
    private let hostOS: HostOS
    private let shellPath: String

    public init(shell: DeviceShell = SystemDeviceShell(), androidSDK: URL? = DeviceParsers.androidSDK(),
                hostOS: HostOS = .current, shellPath: String? = nil) {
        self.shell = shell
        self.androidSDK = androidSDK
        self.hostOS = hostOS
        self.shellPath = shellPath ?? (hostOS == .macOS ? "/bin/zsh" : HostCommand.defaultShell)
    }

    /// iOS simulators exist only on the Mac.
    public var showsIOSSimulators: Bool { Platform.supportsIOSSimulators(on: hostOS) }

    public var androidHint: String? {
        androidSDK == nil ? "Install Android Studio and create a virtual device to see Android emulators here." : nil
    }

    private var emulatorPath: String? { androidSDK?.appendingPathComponent("emulator/emulator").path }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        let showsSimulators = showsIOSSimulators
        async let simJSON: String? = showsSimulators
            ? shell.output(["/usr/bin/xcrun", "simctl", "list", "devices", "available", "-j"]) : nil
        async let flutterJSON = shell.output([shellPath, "-lc", "flutter devices --machine"])
        let avdList: String? = if let emulatorPath { await shell.output([emulatorPath, "-list-avds"]) } else { nil }
        simulators = DeviceParsers.simulators(fromSimctlJSON: await simJSON ?? "")
        avds = DeviceParsers.avds(fromListOutput: avdList ?? "")
        connected = AppModel.parseFlutterDevices(await flutterJSON ?? "")
    }

    public func boot(_ sim: SimulatorDevice) async {
        busy.insert(sim.udid)
        _ = await shell.output(["/usr/bin/xcrun", "simctl", "boot", sim.udid])
        _ = await shell.output(["/usr/bin/open", "-a", "Simulator"])
        busy.remove(sim.udid)
    }

    public func shutdown(_ sim: SimulatorDevice) async {
        busy.insert(sim.udid)
        _ = await shell.output(["/usr/bin/xcrun", "simctl", "shutdown", sim.udid])
        busy.remove(sim.udid)
    }

    public func launch(avd: String) {
        guard let emulatorPath else { return }
        shell.launchDetached([emulatorPath, "-avd", avd])
    }
}
