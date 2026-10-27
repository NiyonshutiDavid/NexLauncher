import Foundation
#if canImport(Glibc)
import Glibc
#endif

public enum HostOS: Sendable, Equatable {
    case macOS, linux

    public static var current: HostOS {
        #if os(macOS)
        .macOS
        #else
        .linux
        #endif
    }
}

/// Where NexLauncher keeps its files, and where it looks for things, on each system.
public struct PlatformPaths: Sendable, Equatable {
    /// Settings and overrides.
    public var configDirectory: URL
    /// Tasks, the widget snapshot, the avatar photo.
    public var dataDirectory: URL
    /// The projects folder suggested on first launch.
    public var defaultScanRoot: URL
    /// Android SDK locations to try, in order.
    public var androidSDKCandidates: [URL]
}

public enum Platform {
    /// Pure version of `paths`, for tests.
    public static func paths(os: HostOS, home: URL, environment: [String: String], exists: (URL) -> Bool) -> PlatformPaths {
        let fromEnv = { (key: String) -> URL? in
            guard let value = environment[key], !value.isEmpty else { return nil }
            return URL(fileURLWithPath: value)
        }
        let androidFromEnv = ["ANDROID_HOME", "ANDROID_SDK_ROOT"].compactMap(fromEnv)
        switch os {
        case .macOS:
            let support = home.appendingPathComponent("Library/Application Support/NexLauncher")
            return PlatformPaths(configDirectory: support, dataDirectory: support,
                                 defaultScanRoot: home.appendingPathComponent("Documents/Nexventures"),
                                 androidSDKCandidates: androidFromEnv + [home.appendingPathComponent("Library/Android/sdk")])
        case .linux:
            let config = (fromEnv("XDG_CONFIG_HOME") ?? home.appendingPathComponent(".config")).appendingPathComponent("nexlauncher")
            let data = (fromEnv("XDG_DATA_HOME") ?? home.appendingPathComponent(".local/share")).appendingPathComponent("nexlauncher")
            // With neither folder, suggest ~/Projects (onboarding offers to create it) rather than scanning all of ~.
            let scan = ["Projects", "Documents"].map { home.appendingPathComponent($0) }.first(where: exists)
                ?? home.appendingPathComponent("Projects")
            return PlatformPaths(configDirectory: config, dataDirectory: data, defaultScanRoot: scan,
                                 androidSDKCandidates: androidFromEnv + [home.appendingPathComponent("Android/Sdk")])
        }
    }

    /// The live paths. `-NexSupportDir <path>` (developer option) puts settings and data in one folder.
    public static var paths: PlatformPaths {
        var p = paths(os: .current, home: AppSettings.realHome, environment: ProcessInfo.processInfo.environment,
                      exists: { FileManager.default.fileExists(atPath: $0.path) })
        if let dir = UserDefaults.standard.string(forKey: "NexSupportDir"), !dir.isEmpty {
            p.configDirectory = URL(fileURLWithPath: dir)
            p.dataDirectory = p.configDirectory
        }
        return p
    }

    /// The shell commands run in: `$SHELL`, else the account's shell, else `/bin/sh`.
    public static func loginShell(environment: [String: String], passwdShell: String?) -> String {
        if let shell = environment["SHELL"], !shell.isEmpty { return shell }
        if let shell = passwdShell, !shell.isEmpty { return shell }
        return "/bin/sh"
    }

    public static var loginShell: String {
        let passwd = getpwuid(getuid()).flatMap { $0.pointee.pw_shell.map { String(cString: $0) } }
        return loginShell(environment: ProcessInfo.processInfo.environment, passwdShell: passwd)
    }

    /// Running inside a Flatpak sandbox, where tools must be started on the host.
    public static var isFlatpak: Bool { FileManager.default.fileExists(atPath: "/.flatpak-info") }

    public static func supportsIOSSimulators(on os: HostOS) -> Bool { os == .macOS }
    public static var supportsIOSSimulators: Bool { supportsIOSSimulators(on: .current) }
}
