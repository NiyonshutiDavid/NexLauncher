import Foundation
import NexCore
import NexGit

struct CloneForm {
    private(set) var url = ""
    private(set) var name = ""
    private var nameEdited = false

    mutating func setURL(_ value: String) {
        url = value
        if !nameEdited { name = ProjectCreator.repositoryName(from: value) }
    }

    mutating func setName(_ value: String) {
        name = value
        nameEdited = true
    }

    func problem(in parent: URL) -> String? {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedURL.isEmpty && !ProjectCreator.isAcceptableURL(trimmedURL) { return ProjectCreationError.invalidURL.errorDescription }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty, let issue = ProjectCreator.validate(name: trimmedName, in: parent) {
            return ProjectCreationError.invalidName(issue).errorDescription
        }
        return nil
    }

    func canSubmit(in parent: URL) -> Bool {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedURL.isEmpty && ProjectCreator.isAcceptableURL(trimmedURL)
            && ProjectCreator.validate(name: name, in: parent) == nil
    }
}

struct NewFolderForm {
    var name = ""
    var initGit = true

    func problem(in parent: URL) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let issue = ProjectCreator.validate(name: trimmed, in: parent) else { return nil }
        return ProjectCreationError.invalidName(issue).errorDescription
    }

    func canSubmit(in parent: URL) -> Bool { ProjectCreator.validate(name: name, in: parent) == nil }
}

enum AvatarPalette {
    static let hexes = ["#cf3f0e", "#1d6fd6", "#1f7a4d", "#7c3aed", "#d97706", "#db2777", "#0f766e", "#475569"]
}

extension PullPreference {
    var strategy: PullStrategy {
        switch self {
        case .ffOnly: return .ffOnly
        case .merge: return .merge
        case .rebase: return .rebase
        }
    }
}
