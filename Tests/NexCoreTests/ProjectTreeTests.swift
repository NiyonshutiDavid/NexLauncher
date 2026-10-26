import Testing
import Foundation
@testable import NexCore

@Suite struct ProjectTreeTests {
    private let flutter = "name: a\ndependencies:\n  flutter:\n    sdk: flutter\n"
    private func tree(_ t: TempTree) -> [ProjectNode] { ProjectScanner().scanTree(root: t.root) }

    @Test func twoFlutterAppsBecomeACollection() {
        let t = TempTree()
        t.write("intern/week3_a/pubspec.yaml", flutter)
        t.write("intern/week3_b/pubspec.yaml", flutter)
        let nodes = tree(t)
        #expect(nodes.count == 1)
        #expect(nodes[0].kind == .collection)
        #expect(nodes[0].name == "intern")
        #expect(nodes[0].project == nil)
        #expect(nodes[0].children.map(\.name) == ["week3_a", "week3_b"])
        #expect(nodes[0].children.allSatisfy { $0.kind == .app && $0.project != nil })
    }

    @Test func frontendPlusBackendStaysOneFullStackApp() {
        let t = TempTree()
        t.write("Centerpiece/Webapp/package.json", TempTree.viteApp)
        t.write("Centerpiece/Backend/requirements.txt", "flask\n")
        t.write("Centerpiece/GreenWonder/package.json", TempTree.viteApp)
        t.write("Centerpiece/MobileApp/pubspec.yaml", flutter)
        let nodes = tree(t)
        #expect(nodes.count == 1)
        #expect(nodes[0].kind == .app)
        #expect(nodes[0].project?.isFullStack == true)
        #expect(nodes[0].project?.targets.count == 4)
        #expect(nodes[0].children.isEmpty)
    }

    @Test func rootManifestWithFlutterSubfolderIsOneApp() {
        let t = TempTree()
        t.write("Jarama/package.json", TempTree.viteApp)
        t.write("Jarama/jarama_mobile/pubspec.yaml", flutter)
        let nodes = tree(t)
        #expect(nodes.count == 1 && nodes[0].kind == .app)
        #expect(Set(nodes[0].project!.targets.map(\.kind)) == [.frontend, .flutter])
        #expect(nodes[0].children.isEmpty)
    }

    @Test func nestedRepoBecomesChildApp() {
        let t = TempTree()
        t.write("Shop/package.json", TempTree.viteApp)
        t.mkdir("Shop/sub/.git")
        t.write("Shop/sub/pubspec.yaml", flutter)
        let node = tree(t)[0]
        #expect(node.kind == .app)
        #expect(node.project!.targets.map(\.kind) == [.frontend])
        #expect(node.children.map(\.name) == ["sub"])
        #expect(node.apps.count == 2)
    }

    @Test func collectionOfCollections() {
        let t = TempTree()
        t.write("sessions/week1/app/pubspec.yaml", flutter)
        t.write("sessions/week2/app/pubspec.yaml", flutter)
        let node = tree(t)[0]
        #expect(node.kind == .collection)
        #expect(node.children.map(\.name) == ["week1", "week2"])
        #expect(node.children.allSatisfy { $0.kind == .app })
        #expect(node.apps.count == 2)
    }

    @Test func singleSlotIsAnApp() {
        let t = TempTree()
        t.write("ijwi-new/ijwi/package.json", TempTree.viteApp)
        let nodes = tree(t)
        #expect(nodes.count == 1 && nodes[0].kind == .app && nodes[0].name == "ijwi-new")
    }

    @Test func manifestsMoreThanTwoLevelsBelowAnAppAreIgnored() {
        let t = TempTree()
        t.write("P/a/b/c/package.json", TempTree.viteApp)          // three levels below P → ignored
        t.write("Q/a/b/package.json", TempTree.viteApp)            // two levels below Q → found
        #expect(tree(t).map(\.name) == ["Q"])
    }

    @Test func nothingBeyondFourLevelsFromTheScanRoot() {
        let t = TempTree()
        t.write("S/w1/x/y/pubspec.yaml", flutter)                  // y is at depth 4 from the root → found
        t.write("S/w2/x/y/pubspec.yaml", flutter)
        t.write("T/w1/x/y/z/pubspec.yaml", flutter)                // z is at depth 5 → ignored
        t.write("T/w2/x/y/z/pubspec.yaml", flutter)
        #expect(tree(t).map(\.name) == ["S"])
    }

    @Test func skipNamesStillSkipped() {
        let t = TempTree()
        t.write("P/node_modules/x/package.json", TempTree.viteApp)
        t.write("P/venv/y/manage.py")
        #expect(tree(t).isEmpty)
    }

    @Test func symlinkLoopTerminates() {
        let t = TempTree()
        t.write("P/a/package.json", TempTree.viteApp)
        t.write("P/b/package.json", TempTree.viteApp)
        t.symlink("P/a/loop", to: "P")
        #expect(tree(t).count == 1)
    }

    @Test func flatScanEqualsAppsOfTree() {
        let t = TempTree()
        t.write("intern/a/pubspec.yaml", flutter); t.write("intern/b/pubspec.yaml", flutter)
        t.write("Site/package.json", TempTree.viteApp)
        let scanner = ProjectScanner()
        #expect(scanner.scan(root: t.root).map(\.id) == scanner.scanTree(root: t.root).flatMap(\.apps).map(\.id))
        #expect(scanner.scan(root: t.root).count == 3)
    }

    @Test func idsAreFolderPathsAndNamesKeepSpaces() {
        let t = TempTree()
        t.write("My Collection/one app/pubspec.yaml", flutter)
        t.write("My Collection/two app/pubspec.yaml", flutter)
        let node = tree(t)[0]
        #expect(node.name == "My Collection")
        #expect(node.id == node.url.path)
        #expect(node.children.map(\.name) == ["one app", "two app"])
        #expect(node.children[0].id == node.children[0].url.path)
    }

    @Test func sameKindMonorepoSlotsFormACollection() {
        let t = TempTree()
        t.write("Mono/web/package.json", TempTree.viteApp)
        t.write("Mono/admin/package.json", TempTree.viteApp)
        #expect(tree(t)[0].kind == .collection)
    }
}

@Suite struct ProjectTreeNestedRepoTests {
    private let flutter = "name: a\ndependencies:\n  flutter:\n    sdk: flutter\n"

    @Test func separateRepoFrontendAndBackendIsOneFullStackApp() {
        let t = TempTree()
        t.mkdir("Proj/frontend/.git"); t.write("Proj/frontend/package.json", TempTree.viteApp)
        t.mkdir("Proj/backend/.git"); t.write("Proj/backend/manage.py")
        let nodes = ProjectScanner().scanTree(root: t.root)
        #expect(nodes.count == 1 && nodes[0].kind == .app)
        #expect(nodes[0].project?.isFullStack == true)
        #expect(nodes[0].project?.targets.count == 2)
    }

    @Test func wrapperWithASingleRepoIsAnApp() {
        let t = TempTree()
        t.mkdir("ijwi-new/ijwi/.git"); t.write("ijwi-new/ijwi/package.json", TempTree.viteApp)
        let nodes = ProjectScanner().scanTree(root: t.root)
        #expect(nodes.count == 1 && nodes[0].kind == .app && nodes[0].name == "ijwi-new")
        #expect(nodes[0].project?.targets.map(\.kind) == [.frontend])
    }

    @Test func wrapperOfSeveralRepoAppsIsACollection() {
        let t = TempTree()
        t.mkdir("Sess/w1/app/.git"); t.write("Sess/w1/app/pubspec.yaml", flutter)
        t.mkdir("Sess/w2/app/.git"); t.write("Sess/w2/app/pubspec.yaml", flutter)
        let nodes = ProjectScanner().scanTree(root: t.root)
        #expect(nodes.count == 1 && nodes[0].kind == .collection)
        #expect(nodes[0].apps.count == 2)
    }

    @Test func v1AndV2AgreeOnWhichFoldersAreProjects() {
        let t = TempTree()
        t.mkdir("A/x/.git"); t.write("A/x/package.json", TempTree.viteApp)
        t.write("B/package.json", TempTree.viteApp)
        t.mkdir("C/only/.git"); t.write("C/only/pubspec.yaml", flutter)
        #expect(ProjectScanner().scan(root: t.root).map(\.name).sorted() == ["A", "B", "C"])
    }
}

@Suite struct SettingsToleranceTests {
    @Test func badEnumValueKeepsEverythingElse() throws {
        let json = #"{"displayName":"Dave","scanRoot":"file:///tmp/x/","showDockIcon":false,"pinnedProjectIDs":["a"],"theme":"sunset","viewMode":"grid","defaultBranch":"trunk"}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(s.displayName == "Dave" && s.pinnedProjectIDs == ["a"] && !s.showDockIcon)
        #expect(s.theme == .ember && s.viewMode == .cards)
        #expect(s.defaultBranch == "trunk")
    }
}
