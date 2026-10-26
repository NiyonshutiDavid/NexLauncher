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
    // polish
    public var onboardingCompleted: Bool = false
    public var notificationsEnabled: Bool = false
    public var notifyReady: Bool = true
    public var notifyCrash: Bool = true
    public var notifyAdded: Bool = true
    public var notifyOnlyInBackground: Bool = true
    public var notifyAgents: Bool = true
    // AI mode
    public var defaultAgent: AgentKind = .claude
    public var agentAutonomy: AgentAutonomy = .edit
    public var customAgentCommand: String = ""
    public var quickPanelShortcutEnabled: Bool = true

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
        // A single unreadable v2 value must not reset everything else.
        func value<T: Decodable>(_ key: Keys) -> T? { (try? c.decodeIfPresent(T.self, forKey: key)) ?? nil }
        appearance = value(.appearance) ?? .system
        theme = value(.theme) ?? .ember
        viewMode = value(.viewMode) ?? .cards
        dismissedCTAs = value(.dismissedCTAs) ?? []
        avatarColorHex = value(.avatarColorHex)
        avatarPhotoPath = value(.avatarPhotoPath)
        lastRun = value(.lastRun)
        defaultBranch = value(.defaultBranch) ?? "main"
        defaultPullStrategy = value(.defaultPullStrategy) ?? .ffOnly
        widgetsConfirmed = value(.widgetsConfirmed) ?? false
        onboardingCompleted = value(.onboardingCompleted) ?? false
        notificationsEnabled = value(.notificationsEnabled) ?? false
        notifyReady = value(.notifyReady) ?? true
        notifyCrash = value(.notifyCrash) ?? true
        notifyAdded = value(.notifyAdded) ?? true
        notifyOnlyInBackground = value(.notifyOnlyInBackground) ?? true
        notifyAgents = value(.notifyAgents) ?? true
        defaultAgent = value(.defaultAgent) ?? .claude
        agentAutonomy = value(.agentAutonomy) ?? .edit
        customAgentCommand = value(.customAgentCommand) ?? ""
        quickPanelShortcutEnabled = value(.quickPanelShortcutEnabled) ?? true
    }

    enum Keys: String, CodingKey {
        case displayName, scanRoot, showDockIcon, pinnedProjectIDs
        case appearance, theme, viewMode, dismissedCTAs, avatarColorHex, avatarPhotoPath, lastRun
        case defaultBranch, defaultPullStrategy, widgetsConfirmed
        case onboardingCompleted, notificationsEnabled, notifyReady, notifyCrash, notifyAdded, notifyOnlyInBackground
        case notifyAgents, defaultAgent, agentAutonomy, customAgentCommand, quickPanelShortcutEnabled
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
