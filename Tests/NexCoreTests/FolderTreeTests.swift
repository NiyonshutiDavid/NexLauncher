import Testing
import Foundation
@testable import NexCore

@Suite struct FolderTreeTests {
    @Test func listsOnlyDirectoriesSorted() {
        let t = TempTree()
        t.mkdir("beta"); t.mkdir("Alpha"); t.write("file.txt", "x")
        #expect(FolderTree.entries(in: t.root).map(\.name) == ["Alpha", "beta"])
    }

    @Test func marksFoldersWithManifestsAsApps() {
        let t = TempTree()
        t.write("site/package.json", TempTree.viteApp)
        t.mkdir("docs")
        let e = FolderTree.entries(in: t.root)
        #expect(e.first { $0.name == "site" }?.isApp == true)
        #expect(e.first { $0.name == "docs" }?.isApp == false)
    }

    @Test func skipsNodeModulesAndHidden() {
        let t = TempTree()
        t.mkdir("node_modules"); t.mkdir(".git"); t.mkdir("src")
        #expect(FolderTree.entries(in: t.root).map(\.name) == ["src"])
    }

    @Test func hasSubfoldersFlag() {
        let t = TempTree()
        t.mkdir("a/b"); t.mkdir("leaf")
        let e = FolderTree.entries(in: t.root)
        #expect(e.first { $0.name == "a" }?.hasSubfolders == true)
        #expect(e.first { $0.name == "leaf" }?.hasSubfolders == false)
    }

    @Test func missingDirectoryReturnsEmpty() {
        #expect(FolderTree.entries(in: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")).isEmpty)
    }

    @Test func symlinkedDirectoryIsListedOnceWithoutRecursing() {
        let t = TempTree()
        t.mkdir("real/inner")
        t.symlink("link", to: "real")
        let e = FolderTree.entries(in: t.root)
        #expect(e.map(\.name) == ["link", "real"])
        #expect(e.first { $0.name == "link" }?.hasSubfolders == false)   // not followed
    }

    @Test func idsAreFolderPaths() {
        let t = TempTree()
        t.mkdir("My Folder")
        let e = FolderTree.entries(in: t.root)[0]
        #expect(e.id == e.url.path && e.name == "My Folder")
    }
}
