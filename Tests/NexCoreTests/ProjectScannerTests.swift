import Testing
import Foundation
@testable import NexCore

@Suite struct ProjectScannerTests {
    private func scan(_ t: TempTree) -> [Project] { ProjectScanner().scan(root: t.root) }
    private func kinds(_ p: Project) -> Set<ServiceKind> { Set(p.targets.map(\.kind)) }

    @Test func djangoPlusViteIsFullStack() {
        let t = TempTree()
        t.write("CleanPay/frontend/package.json", TempTree.viteApp)
        t.write("CleanPay/backend/manage.py")
        let p = scan(t)
        #expect(p.count == 1)
        #expect(p[0].isFullStack)
        #expect(p[0].targets.first { $0.kind == .frontend }?.framework == "Vite")
    }

    @Test(arguments: [("client", "server"), ("web", "api"), ("Clients", "Server")])
    func differentFolderNamesStillDetected(front: String, back: String) {
        let t = TempTree()
        t.write("P/\(front)/package.json", TempTree.viteApp)
        t.write("P/\(back)/requirements.txt", "fastapi==0.1\nuvicorn\n")
        let p = scan(t)
        #expect(p.count == 1)
        #expect(kinds(p[0]) == [.frontend, .backend])
    }

    @Test func expressPackageIsBackend() {
        let t = TempTree()
        t.write("P/server/package.json", #"{"scripts":{"start":"node index.js"},"dependencies":{"express":"4"}}"#)
        #expect(kinds(scan(t)[0]) == [.backend])
    }

    @Test func flutterDetectedFromPubspec() {
        let t = TempTree()
        t.write("P/mobile/pubspec.yaml", "name: app\ndependencies:\n  flutter:\n    sdk: flutter\n")
        #expect(kinds(scan(t)[0]) == [.flutter])
    }

    @Test func dockerComposeDetected() {
        let t = TempTree()
        t.write("BTN Limited/docker-compose.yml", "services: {}")
        #expect(kinds(scan(t)[0]) == [.docker])
    }

    @Test func nodeModulesIgnored() {
        let t = TempTree()
        t.write("P/package.json", TempTree.viteApp)
        t.write("P/node_modules/dep/package.json", TempTree.viteApp)
        t.write("P/node_modules/dep/manage.py")
        #expect(scan(t)[0].targets.count == 1)
    }

    @Test func frontendOnlyProject() {
        let t = TempTree()
        t.write("Site/package.json", TempTree.viteApp)
        let p = scan(t)[0]
        #expect(!p.isFullStack)
        #expect(kinds(p) == [.frontend])
    }

    @Test func scriptlessPackageJsonIsNotFrontend() {
        let t = TempTree()
        t.write("Lib/package.json", #"{"name":"lib","dependencies":{"react":"1"}}"#)
        #expect(scan(t).isEmpty)
    }

    @Test func malformedPackageJsonSkippedNotCrash() {
        let t = TempTree()
        t.write("Bad/package.json", "{ not json")
        t.write("Good/package.json", TempTree.viteApp)
        let p = scan(t)
        #expect(p.map(\.name) == ["Good"])
    }

    @Test func emptyRootReturnsEmpty() {
        #expect(scan(TempTree()).isEmpty)
    }

    @Test func missingRootReturnsEmpty() {
        #expect(ProjectScanner().scan(root: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")).isEmpty)
    }

    @Test func symlinkLoopTerminates() {
        let t = TempTree()
        t.write("P/frontend/package.json", TempTree.viteApp)
        t.symlink("P/frontend/loop", to: "P")
        #expect(scan(t).count == 1)
    }

    @Test func folderWithSpacesKeepsName() {
        let t = TempTree()
        t.write("Kigali Height Proposal/web/package.json", TempTree.viteApp)
        #expect(scan(t)[0].name == "Kigali Height Proposal")
    }

    @Test func nexLauncherFolderSkipped() {
        let t = TempTree()
        t.write("NexLauncher/package.json", TempTree.viteApp)
        #expect(scan(t).isEmpty)
    }

    @Test func projectsWithoutManifestsOmitted() {
        let t = TempTree()
        t.write("Notes/README.md", "hi")
        #expect(scan(t).isEmpty)
    }

    @Test func detectsTargetsTwoLevelsDeep() {
        let t = TempTree()
        t.write("BTN/apps/web/package.json", TempTree.viteApp)
        t.write("BTN/apps/api/manage.py")
        #expect(kinds(scan(t)[0]) == [.frontend, .backend])
    }
}
