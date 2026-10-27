import Foundation
import Observation
import NexCore

public enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome, name, projects, git, look, ai, extras

    public var illustration: IllustrationKind {
        switch self {
        case .welcome: return .rocket
        case .name: return .power
        case .projects: return .folders
        case .git: return .branchGraph
        case .look: return .swatches
        case .ai: return .robot
        case .extras: return .widgets
        }
    }
}

/// The first-launch walkthrough. It collects choices and applies them all at once on `finish()`.
@MainActor @Observable
public final class OnboardingModel {
    public var step: OnboardingStep = .welcome
    public var name: String
    public var folder: URL
    public var gitName = ""
    public var gitEmail = ""
    public var theme: ThemeID
    public var appearance: AppearanceMode
    public var notifications = false
    public var launchAtLogin = false
    public var defaultAgent: AgentKind
    public var autonomy: AgentAutonomy
    public private(set) var detectedCount: Int?
    public private(set) var isFinishing = false
    let model: AppModel

    public init(model: AppModel) {
        self.model = model
        name = model.settings.settings.displayName
        folder = model.settings.settings.scanRoot
        theme = model.settings.settings.theme
        appearance = model.settings.settings.appearance
        defaultAgent = model.settings.settings.defaultAgent
        autonomy = model.settings.settings.agentAutonomy
    }

    public var folderExists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Creates the chosen projects folder (a fresh Linux account often has none).
    public func createFolder() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    public var isFirst: Bool { step == .welcome }
    public var isLast: Bool { step == .extras }
    public var progress: Double { Double(step.rawValue) / Double(OnboardingStep.allCases.count - 1) }

    public var canAdvance: Bool {
        switch step {
        case .name: return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .projects: return folderExists
        default: return true
        }
    }

    public func next() {
        guard canAdvance, let following = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = following
    }

    public func back() {
        if let previous = OnboardingStep(rawValue: step.rawValue - 1) { step = previous }
    }

    /// Counts the projects NexLauncher would find in the chosen folder.
    public func scanFolder() async {
        guard folderExists else { detectedCount = nil; return }
        let root = folder
        detectedCount = await Task.detached { ProjectScanner().scan(root: root).count }.value
    }

    /// Prefills the git fields from the user's existing global configuration.
    public func loadExisting() async {
        name = model.settings.settings.displayName
        let identity = try? await model.git.identity(AppSettings.realHome, scope: .global)
        gitName = identity?.name ?? ""
        gitEmail = identity?.email ?? ""
    }

    public func finish() async {
        isFinishing = true
        defer { isFinishing = false }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { model.settings.settings.displayName = trimmed }
        model.settings.settings.scanRoot = folder
        model.settings.settings.theme = theme
        model.settings.settings.appearance = appearance
        model.settings.settings.defaultAgent = defaultAgent
        model.settings.settings.agentAutonomy = autonomy
        model.settings.save()
        let gn = gitName.trimmingCharacters(in: .whitespaces), ge = gitEmail.trimmingCharacters(in: .whitespaces)
        if !gn.isEmpty && !ge.isEmpty { try? await model.saveGitIdentity(name: gn, email: ge) }
        if notifications { await model.setNotificationsEnabled(true) }
        if launchAtLogin { model.login.set(true) }
        model.settings.settings.onboardingCompleted = true
        model.settings.save()
        await model.refresh()
    }
}

extension AppModel {
    public var showOnboarding: Bool { !settings.settings.onboardingCompleted }

    public func skipOnboarding() {
        settings.settings.onboardingCompleted = true
        settings.save()
    }

    public func replayOnboarding() {
        settings.settings.onboardingCompleted = false
        settings.save()
    }
}
