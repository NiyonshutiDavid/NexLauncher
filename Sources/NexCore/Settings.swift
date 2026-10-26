import Foundation
import Observation

public enum AppearanceMode: String, Codable, CaseIterable, Sendable { case system, light, dark }
public enum ThemeID: String, Codable, CaseIterable, Sendable { case ember, ocean, forest, violet, graphite }
public enum ViewMode: String, Codable, Sendable { case cards, folders }
public enum PullPreference: String, Codable, CaseIterable, Sendable { case ffOnly, merge, rebase }

public struct LastRun: Codable, Equatable, Sendable {
    public var projectID: String
    public var action: String
    public init(projectID: String, action: String) {
        self.projectID = projectID
        self.action = action
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var displayName: String
    public var scanRoot: URL
    public var showDockIcon: Bool
    public var pinnedProjectIDs: [String]
    // v2
    public var appearance: AppearanceMode = .system
    public var theme: ThemeID = .ember
    public var viewMode: ViewMode = .cards
    public var dismissedCTAs: Set<String> = []
    public var avatarColorHex: String? = nil
    public var avatarPhotoPath: String? = nil
    public var lastRun: LastRun? = nil
    public var defaultBranch: String = "main"
    public var defaultPullStrategy: PullPreference = .ffOnly
    public var widgetsConfirmed: Bool = false

    public init(displayName: String, scanRoot: URL, showDockIcon: Bool, pinnedProjectIDs: [String]) {
        self.displayName = displayName
        self.scanRoot = scanRoot
        self.showDockIcon = showDockIcon
        self.pinnedProjectIDs = pinnedProjectIDs
    }

    /// Every v2 key is optional so settings written by v1 keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        displayName = try c.decode(String.self, forKey: .displayName)
        scanRoot = try c.decode(URL.self, forKey: .scanRoot)
        showDockIcon = try c.decode(Bool.self, forKey: .showDockIcon)
        pinnedProjectIDs = try c.decode([String].self, forKey: .pinnedProjectIDs)
        appearance = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? .system
        theme = try c.decodeIfPresent(ThemeID.self, forKey: .theme) ?? .ember
        viewMode = try c.decodeIfPresent(ViewMode.self, forKey: .viewMode) ?? .cards
        dismissedCTAs = try c.decodeIfPresent(Set<String>.self, forKey: .dismissedCTAs) ?? []
        avatarColorHex = try c.decodeIfPresent(String.self, forKey: .avatarColorHex)
        avatarPhotoPath = try c.decodeIfPresent(String.self, forKey: .avatarPhotoPath)
        lastRun = try c.decodeIfPresent(LastRun.self, forKey: .lastRun)
        defaultBranch = try c.decodeIfPresent(String.self, forKey: .defaultBranch) ?? "main"
        defaultPullStrategy = try c.decodeIfPresent(PullPreference.self, forKey: .defaultPullStrategy) ?? .ffOnly
        widgetsConfirmed = try c.decodeIfPresent(Bool.self, forKey: .widgetsConfirmed) ?? false
    }

    enum Keys: String, CodingKey {
        case displayName, scanRoot, showDockIcon, pinnedProjectIDs
        case appearance, theme, viewMode, dismissedCTAs, avatarColorHex, avatarPhotoPath, lastRun
        case defaultBranch, defaultPullStrategy, widgetsConfirmed
    }

    public static func initials(from name: String) -> String {
        let letters = name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    public static func firstName(from fullName: String) -> String {
        fullName.split(separator: " ").first.map(String.init) ?? "there"
    }

    /// The user's real home folder, even inside a sandbox (where `homeDirectoryForCurrentUser` is the container).
    public static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir { return URL(fileURLWithPath: String(cString: dir)) }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public static func defaults() -> AppSettings {
        AppSettings(
            displayName: firstName(from: NSFullUserName()),
            scanRoot: realHome.appendingPathComponent("Documents/Nexventures"),
            showDockIcon: true,
            pinnedProjectIDs: [])
    }

    public static var supportDirectory: URL {
        realHome.appendingPathComponent("Library/Application Support/NexLauncher")
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
