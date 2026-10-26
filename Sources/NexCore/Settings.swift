import Foundation
import Observation

public struct AppSettings: Codable, Equatable, Sendable {
    public var displayName: String
    public var scanRoot: URL
    public var showDockIcon: Bool
    public var pinnedProjectIDs: [String]

    public static func firstName(from fullName: String) -> String {
        fullName.split(separator: " ").first.map(String.init) ?? "there"
    }

    public static func defaults() -> AppSettings {
        AppSettings(
            displayName: firstName(from: NSFullUserName()),
            scanRoot: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Nexventures"),
            showDockIcon: true,
            pinnedProjectIDs: [])
    }

    public static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/NexLauncher")
    }
}

@Observable
public final class SettingsStore {
    public var settings: AppSettings
    private let fileURL: URL

    public init(fileURL: URL = AppSettings.supportDirectory.appendingPathComponent("settings.json")) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL), let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .defaults()
        }
    }

    public func save() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(settings) { try? data.write(to: fileURL, options: .atomic) }
    }
}
