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
    /// Keys this version doesn't know (written by a newer version or the other platform), kept as they were.
    public var extras: [String: JSONValue] = [:]

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
        let all = try decoder.container(keyedBy: AnyKey.self)
        for key in all.allKeys where Keys(rawValue: key.stringValue) == nil {
            if let v = try? all.decode(JSONValue.self, forKey: key) { extras[key.stringValue] = v }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var extra = encoder.container(keyedBy: AnyKey.self)
        for (key, v) in extras where Keys(rawValue: key) == nil { try extra.encode(v, forKey: AnyKey(key)) }
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(scanRoot, forKey: .scanRoot)
        try c.encode(showDockIcon, forKey: .showDockIcon)
        try c.encode(pinnedProjectIDs, forKey: .pinnedProjectIDs)
        try c.encode(appearance, forKey: .appearance)
        try c.encode(theme, forKey: .theme)
        try c.encode(viewMode, forKey: .viewMode)
        try c.encode(dismissedCTAs, forKey: .dismissedCTAs)
        try c.encodeIfPresent(avatarColorHex, forKey: .avatarColorHex)
        try c.encodeIfPresent(avatarPhotoPath, forKey: .avatarPhotoPath)
        try c.encodeIfPresent(lastRun, forKey: .lastRun)
        try c.encode(defaultBranch, forKey: .defaultBranch)
        try c.encode(defaultPullStrategy, forKey: .defaultPullStrategy)
        try c.encode(widgetsConfirmed, forKey: .widgetsConfirmed)
        try c.encode(onboardingCompleted, forKey: .onboardingCompleted)
        try c.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try c.encode(notifyReady, forKey: .notifyReady)
        try c.encode(notifyCrash, forKey: .notifyCrash)
        try c.encode(notifyAdded, forKey: .notifyAdded)
        try c.encode(notifyOnlyInBackground, forKey: .notifyOnlyInBackground)
        try c.encode(notifyAgents, forKey: .notifyAgents)
        try c.encode(defaultAgent, forKey: .defaultAgent)
        try c.encode(agentAutonomy, forKey: .agentAutonomy)
        try c.encode(customAgentCommand, forKey: .customAgentCommand)
        try c.encode(quickPanelShortcutEnabled, forKey: .quickPanelShortcutEnabled)
    }

    struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
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
            scanRoot: Platform.paths.defaultScanRoot,
            showDockIcon: true,
            pinnedProjectIDs: [])
    }

    /// Settings and overrides (see `Platform.paths`).
    public static var supportDirectory: URL { Platform.paths.configDirectory }
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

/// Any JSON value, for settings keys this version doesn't know.
public enum JSONValue: Codable, Equatable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}
