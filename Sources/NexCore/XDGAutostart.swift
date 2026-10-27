import Foundation

/// Launch at login on Linux desktops: a `.desktop` file in the XDG autostart folder.
public struct XDGAutostart: LoginItemControlling {
    public let directory: URL
    public let exec: String
    public static let fileName = "net.nexventures.NexLauncher.desktop"

    public init(directory: URL, exec: String) {
        self.directory = directory
        self.exec = exec
    }

    /// `~/.config/autostart` (or `$XDG_CONFIG_HOME/autostart`), starting the Flatpak or this binary.
    public static func forCurrentUser(environment: [String: String] = ProcessInfo.processInfo.environment) -> XDGAutostart {
        let config = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? AppSettings.realHome.appendingPathComponent(".config")
        let exec = Platform.isFlatpak ? "flatpak run net.nexventures.NexLauncher" : (CommandLine.arguments.first ?? "nexlauncher")
        return XDGAutostart(directory: config.appendingPathComponent("autostart"), exec: exec)
    }

    private var file: URL { directory.appendingPathComponent(Self.fileName) }

    public var isEnabled: Bool { FileManager.default.fileExists(atPath: file.path) }

    public func setEnabled(_ on: Bool) throws {
        guard on else {
            if isEnabled { try FileManager.default.removeItem(at: file) }
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let entry = """
        [Desktop Entry]
        Type=Application
        Name=NexLauncher
        Exec=\(exec)
        Icon=net.nexventures.NexLauncher
        X-GNOME-Autostart-enabled=true
        """
        try (entry + "\n").write(to: file, atomically: true, encoding: .utf8)
    }
}
