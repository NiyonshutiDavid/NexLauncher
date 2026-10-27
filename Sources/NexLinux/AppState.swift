import Foundation
import Observation
import Adwaita
import NexApp
import NexCore
import NexProcess

/// Bridges Observation to Adwaita for Swift: whenever anything the views read from `AppModel` changes, the
/// window re-renders (SwiftUI does this by itself on the Mac).
struct AppState: Model {
    var model: ModelData?
    var tick = 0
    let app: AppModel

    init(app: AppModel) { self.app = app }

    mutating func setup() { observe() }

    func observe() {
        withObservationTracking { app.touchViewState() } onChange: {
            // onChange fires before the new value is stored: re-render on the next main-loop turn.
            MainActor.assumeIsolated {
                Idle {
                    setModel { $0.tick &+= 1 }
                    observe()
                }
            }
        }
    }
}

extension AppModel {
    /// Reads every observable value the Linux views show, so `AppState` hears about changes to any of them.
    func touchViewState() {
        _ = (projects, tree, isScanning, searchText, filter, filters, aiPanelProjectID, gitBadges, page, sheet,
             showOnlyUncommitted, statusMessage, gitBusy, detailTab, refreshToken, tasks, agentDraft, agentError,
             setup, pendingInstall, settings.settings, processes.states, processes.logs)
        for run in agentRuns { _ = (run.events, run.status) }
    }
}
