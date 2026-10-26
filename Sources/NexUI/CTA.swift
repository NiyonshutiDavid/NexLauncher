import Foundation
import NexCore

public enum CTAID: String, CaseIterable, Sendable {
    case addProject = "add-project"
    case gitIdentity = "git-identity"
    case uncommitted, resume, themes, widgets, login
}

/// Everything the engine needs to decide which cards apply.
public struct CTAContext: Sendable {
    public var gitIdentitySet: Bool
    public var projectsWithChanges: Int
    public var lastRunName: String?
    public var anythingRunning: Bool
    public var themeChanged: Bool
    public var widgetsConfirmed: Bool
    public var launchAtLogin: Bool

    public init(gitIdentitySet: Bool, projectsWithChanges: Int, lastRunName: String?, anythingRunning: Bool,
                themeChanged: Bool, widgetsConfirmed: Bool, launchAtLogin: Bool) {
        self.gitIdentitySet = gitIdentitySet
        self.projectsWithChanges = projectsWithChanges
        self.lastRunName = lastRunName
        self.anythingRunning = anythingRunning
        self.themeChanged = themeChanged
        self.widgetsConfirmed = widgetsConfirmed
        self.launchAtLogin = launchAtLogin
    }
}

public struct CTA: Identifiable, Equatable, Sendable {
    public let id: CTAID
    public let headline: String
    public let body: String
    public let button: String
    public let illustration: IllustrationKind
}

public enum CTAEngine {
    /// Applicable, non-dismissed cards in priority order, capped at `limit`.
    public static func visible(_ c: CTAContext, dismissed: Set<String>, limit: Int = 3) -> [CTA] {
        var all: [CTA] = []
        if !c.gitIdentitySet {
            all.append(CTA(id: .gitIdentity, headline: "Tell git who you are",
                           body: "Add your name and email so your commits carry your name.",
                           button: "Set up", illustration: .branchGraph))
        }
        if c.projectsWithChanges > 0 {
            let n = c.projectsWithChanges
            all.append(CTA(id: .uncommitted,
                           headline: n == 1 ? "1 project has unsaved changes" : "\(n) projects have unsaved changes",
                           body: "Review what changed and commit it before it gets lost.",
                           button: "Review", illustration: .folders))
        }
        if let name = c.lastRunName, !c.anythingRunning {
            all.append(CTA(id: .resume, headline: "Pick up where you left off",
                           body: "Start \(name) again with the same setup.",
                           button: "Run \(name)", illustration: .terminal))
        }
        all.append(CTA(id: .addProject, headline: "Start something new",
                       body: "Create a folder or clone a repository and it shows up here.",
                       button: "Add project", illustration: .rocket))
        if !c.launchAtLogin {
            all.append(CTA(id: .login, headline: "Start with your Mac",
                           body: "Open NexLauncher when you log in so your projects are one click away.",
                           button: "Turn on", illustration: .power))
        }
        if !c.themeChanged {
            all.append(CTA(id: .themes, headline: "Make it yours",
                           body: "Pick a theme and light or dark appearance.",
                           button: "Choose a theme", illustration: .swatches))
        }
        if !c.widgetsConfirmed {
            all.append(CTA(id: .widgets, headline: "Keep an eye on your servers",
                           body: "Add the Running Services widget to your desktop.",
                           button: "Show me how", illustration: .widgets))
        }
        return Array(all.filter { !dismissed.contains($0.id.rawValue) }.prefix(limit))
    }
}
