import Foundation

public struct SimulatorDevice: Identifiable, Equatable, Hashable, Sendable {
    public let udid: String
    public let name: String
    public let runtime: String
    public var isBooted: Bool
    public var id: String { udid }

    public init(udid: String, name: String, runtime: String, isBooted: Bool) {
        self.udid = udid
        self.name = name
        self.runtime = runtime
        self.isBooted = isBooted
    }
}

/// Parsers for simulator and emulator tool output. Pure, so they're tested with fixtures.
public enum DeviceParsers {
    /// iOS simulators from `xcrun simctl list devices available -j`, booted first, then by name.
    public static func simulators(fromSimctlJSON json: String) -> [SimulatorDevice] {
        guard let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let devices = root["devices"] as? [String: [[String: Any]]] else { return [] }
        var out: [SimulatorDevice] = []
        for (runtimeKey, list) in devices {
            // "com.apple.CoreSimulator.SimRuntime.iOS-26-0" → "iOS 26.0"
            guard let tail = runtimeKey.split(separator: ".").last, tail.hasPrefix("iOS-") else { continue }
            let parts = tail.split(separator: "-")
            let runtime = "iOS " + parts.dropFirst().joined(separator: ".")
            for d in list where (d["isAvailable"] as? Bool) ?? true {
                guard let udid = d["udid"] as? String, let name = d["name"] as? String else { continue }
                out.append(SimulatorDevice(udid: udid, name: name, runtime: runtime, isBooted: (d["state"] as? String) == "Booted"))
            }
        }
        return out.sorted { a, b in
            if a.isBooted != b.isBooted { return a.isBooted }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// AVD names from `emulator -list-avds` (log lines like "INFO | …" are skipped).
    public static func avds(fromListOutput output: String) -> [String] {
        output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains("|") && !$0.contains(" ") }
    }

    public static func displayName(forAVD avd: String) -> String { avd.replacingOccurrences(of: "_", with: " ") }

    /// The Android SDK: $ANDROID_HOME, $ANDROID_SDK_ROOT, or Android Studio's default location.
    public static func androidSDK(environment: [String: String] = ProcessInfo.processInfo.environment,
                                  home: URL = AppSettings.realHome) -> URL? {
        let candidates = [environment["ANDROID_HOME"], environment["ANDROID_SDK_ROOT"]].compactMap { $0 }.map { URL(fileURLWithPath: $0) }
            + [home.appendingPathComponent("Library/Android/sdk")]
        return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("emulator/emulator").path) }
    }
}
