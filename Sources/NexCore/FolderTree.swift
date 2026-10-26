import Foundation

public struct FolderEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let url: URL
    /// The folder has its own runnable manifest (package.json, manage.py, pubspec.yaml, …).
    public let isApp: Bool
    public let hasSubfolders: Bool
}

/// One level of the on-disk folder structure, listed lazily as the Folders view expands.
public enum FolderTree {
    public static func entries(in directory: URL, skipNames: Set<String> = ProjectScanner.defaultSkips) -> [FolderEntry] {
        subfolders(of: directory, skipNames: skipNames, followSymlinks: true)
            .map { url in
                let isLink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
                return FolderEntry(
                    id: url.path, name: url.lastPathComponent, url: url,
                    isApp: !ProjectScanner.detect(in: url).isEmpty,
                    hasSubfolders: !isLink && !subfolders(of: url, skipNames: skipNames, followSymlinks: false).isEmpty)
            }
    }

    private static func subfolders(of dir: URL, skipNames: Set<String>, followSymlinks: Bool) -> [URL] {
        let kids = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])) ?? []
        return kids.filter { url in
            guard !skipNames.contains(url.lastPathComponent),
                  let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
            if v.isSymbolicLink == true {
                return followSymlinks && (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            return v.isDirectory == true
        }.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }
}
