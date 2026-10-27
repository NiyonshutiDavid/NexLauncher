import Foundation
import NexCore
import NexGit

public struct CloneForm {
    public init() {}
    public private(set) var url = ""
    public private(set) var name = ""
    private var nameEdited = false

    public mutating func setURL(_ value: String) {
        url = value
        if !nameEdited { name = ProjectCreator.repositoryName(from: value) }
    }

    public mutating func setName(_ value: String) {
        name = value
        nameEdited = true
    }

    public func problem(in parent: URL) -> String? {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedURL.isEmpty && !ProjectCreator.isAcceptableURL(trimmedURL) { return ProjectCreationError.invalidURL.errorDescription }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty, let issue = ProjectCreator.validate(name: trimmedName, in: parent) {
            return ProjectCreationError.invalidName(issue).errorDescription
        }
        return nil
    }

    public func canSubmit(in parent: URL) -> Bool {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedURL.isEmpty && ProjectCreator.isAcceptableURL(trimmedURL)
            && ProjectCreator.validate(name: name, in: parent) == nil
    }
}

public struct NewFolderForm {
    public var name = ""
    public var initGit = true
    public init() {}

    public func problem(in parent: URL) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let issue = ProjectCreator.validate(name: trimmed, in: parent) else { return nil }
        return ProjectCreationError.invalidName(issue).errorDescription
    }

    public func canSubmit(in parent: URL) -> Bool { ProjectCreator.validate(name: name, in: parent) == nil }
}

public enum AvatarPalette {
    public static let hexes = ["#cf3f0e", "#1d6fd6", "#1f7a4d", "#7c3aed", "#d97706", "#db2777", "#0f766e", "#475569"]
}


