import Foundation
import Observation
import NexCore

/// Runs device tools. A protocol so tests can check the exact commands.
public protocol DeviceShell: Sendable {
    func output(_ args: [String]) async -> String?
    func launchDetached(_ args: [String])
}

public struct SystemDeviceShell: DeviceShell {
    public init() {}

    public func output(_ args: [String]) async -> String? {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: args[0])
            p.arguments = Array(args.dropFirst())
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
        let p = Process()
        p.executableURL = URL(fileURLWithPath: args[0])
        p.arguments = Array(args.dropFirst())
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

    public init(shell: DeviceShell = SystemDeviceShell(), androidSDK: URL? = DeviceParsers.androidSDK()) {
        self.shell = shell
        self.androidSDK = androidSDK
    }

    public var androidHint: String? {
        androidSDK == nil ? "Install Android Studio and create a virtual device to see Android emulators here." : nil
    }

    private var emulatorPath: String? { androidSDK?.appendingPathComponent("emulator/emulator").path }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        async let simJSON = shell.output(["/usr/bin/xcrun", "simctl", "list", "devices", "available", "-j"])
        async let flutterJSON = shell.output(["/bin/zsh", "-lc", "flutter devices --machine"])
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
