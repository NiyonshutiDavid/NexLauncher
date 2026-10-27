import Foundation
import NexCore
import NexGit

extension PullPreference {
    /// The git pull strategy for this setting.
    public var strategy: PullStrategy {
        switch self {
        case .ffOnly: return .ffOnly
        case .merge: return .merge
        case .rebase: return .rebase
        }
    }
}
