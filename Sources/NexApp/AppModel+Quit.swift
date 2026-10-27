import Foundation

extension AppModel {
    /// What quitting would interrupt, as a sentence for the confirmation; nil when nothing is running.
    public var quitSummary: String? {
        let services = processes.runningCount, agents = runningAgentCount
        var parts: [String] = []
        if services > 0 { parts.append("\(services) service\(services == 1 ? "" : "s") still running") }
        if terminals.hasRunningPrograms { parts.append("a program is still running in a terminal") }
        if agents > 0 { parts.append("\(agents) AI agent\(agents == 1 ? " is" : "s are") still working") }
        guard !parts.isEmpty else { return nil }
        let sentence = parts.joined(separator: " and ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }

    /// Stops every service and agent (never leave an agent editing files unsupervised) and closes the terminals.
    public func stopEverything() async {
        await stopAllServices()
        await stopAllAgents()
        terminals.closeAll()
    }
}
