import Testing
import Foundation
@testable import NexCore

@Suite struct CommandBuilderTests {
    @Test func nodeUsesNpmRunDev() {
        let t = TempTree()
        t.write("P/package.json", TempTree.viteApp)
        let cmd = CommandBuilder.command(for: .frontend, at: t.root.appendingPathComponent("P"), framework: "Vite", flutterDevice: nil)
        #expect(cmd.hasSuffix("&& npm run dev"))
    }

    @Test func nodeFallsBackToStart() {
        let t = TempTree()
        t.write("P/package.json", #"{"scripts":{"start":"node a.js"},"dependencies":{"express":"4"}}"#)
        let cmd = CommandBuilder.command(for: .backend, at: t.root.appendingPathComponent("P"), framework: "Express", flutterDevice: nil)
        #expect(cmd.hasSuffix("&& npm start"))
    }

    @Test func djangoUsesVenvPythonWhenPresent() {
        let t = TempTree()
        t.write("api/manage.py")
        t.mkdir("api/venv/bin")
        t.write("api/venv/bin/python")
        let cmd = CommandBuilder.command(for: .backend, at: t.root.appendingPathComponent("api"), framework: "Django", flutterDevice: nil)
        #expect(cmd.hasSuffix("&& venv/bin/python manage.py runserver"))
    }

    @Test func djangoPlainPython3WithoutVenv() {
        let t = TempTree()
        t.write("api/manage.py")
        let cmd = CommandBuilder.command(for: .backend, at: t.root.appendingPathComponent("api"), framework: "Django", flutterDevice: nil)
        #expect(cmd.hasSuffix("&& python3 manage.py runserver"))
    }

    @Test func fastAPIUsesUvicorn() {
        let t = TempTree()
        t.write("api/requirements.txt", "fastapi\n")
        let cmd = CommandBuilder.command(for: .backend, at: t.root.appendingPathComponent("api"), framework: "FastAPI", flutterDevice: nil)
        #expect(cmd.hasSuffix("&& python3 -m uvicorn main:app --reload"))
    }

    @Test func djangoWithPackageJsonStillRunsDjango() {
        let t = TempTree()
        t.write("site/manage.py")
        t.write("site/package.json", #"{"scripts":{"dev":"tailwindcss -w"}}"#)
        let cmd = CommandBuilder.command(for: .backend, at: t.root.appendingPathComponent("site"), framework: "Django", flutterDevice: nil)
        #expect(cmd.hasSuffix("&& python3 manage.py runserver"))
    }

    @Test func flutterDeviceIsShellQuoted() {
        let cmd = CommandBuilder.command(for: .flutter, at: URL(fileURLWithPath: "/tmp/m"), framework: nil, flutterDevice: "my phone;rm")
        #expect(cmd.hasSuffix("&& flutter run -d 'my phone;rm'"))
    }

    @Test func flutterIncludesDevice() {
        let cmd = CommandBuilder.command(for: .flutter, at: URL(fileURLWithPath: "/tmp/m"), framework: nil, flutterDevice: "macos")
        #expect(cmd.hasSuffix("&& flutter run -d macos"))
    }

    @Test func dockerComposeUp() {
        let cmd = CommandBuilder.command(for: .docker, at: URL(fileURLWithPath: "/tmp/d"), framework: nil, flutterDevice: nil)
        #expect(cmd.hasSuffix("&& docker compose up"))
    }

    @Test func needsInstallWhenNodeModulesMissing() {
        let t = TempTree()
        t.write("P/package.json", TempTree.viteApp)
        let target = ServiceTarget(kind: .frontend, directory: t.root.appendingPathComponent("P"), framework: nil, command: "")
        #expect(CommandBuilder.needsInstall(target))
        t.mkdir("P/node_modules")
        #expect(!CommandBuilder.needsInstall(target))
        #expect(CommandBuilder.installCommand(for: target).hasSuffix("&& npm install"))
    }

    @Test func djangoNeverNeedsNodeInstall() {
        let t = TempTree()
        t.write("api/manage.py")
        let target = ServiceTarget(kind: .backend, directory: t.root.appendingPathComponent("api"), framework: "Django", command: "")
        #expect(!CommandBuilder.needsInstall(target))
    }

    @Test func pathWithSpacesAndQuotesIsQuoted() {
        let dir = URL(fileURLWithPath: "/tmp/BTN Limited's Management system/apps")
        let cmd = CommandBuilder.command(for: .docker, at: dir, framework: nil, flutterDevice: nil)
        #expect(cmd.hasPrefix(#"cd '/tmp/BTN Limited'\''s Management system/apps' && "#))
    }
}

@Suite struct OverrideAndScannerCommandTests {
    @Test func overridePersistsAcrossReload() {
        let t = TempTree()
        let file = t.root.appendingPathComponent("overrides.json")
        OverrideStore(fileURL: file).set(Override(kind: nil, command: "make run", port: 8080), forPath: "/p|frontend")
        let loaded = OverrideStore(fileURL: file).override(forPath: "/p|frontend")
        #expect(loaded?.command == "make run")
        #expect(loaded?.port == 8080)
    }

    @Test func scannerFillsDefaultCommands() {
        let t = TempTree()
        t.write("P/package.json", TempTree.viteApp)
        let target = ProjectScanner().scan(root: t.root)[0].targets[0]
        #expect(target.command.hasSuffix("&& npm run dev"))
    }

    @Test func overrideCommandReplacesDefaultAndSetsPort() {
        let t = TempTree()
        t.write("P/package.json", TempTree.viteApp)
        let store = OverrideStore(fileURL: t.root.appendingPathComponent("o.json"))
        let dir = t.root.appendingPathComponent("P")
        store.set(Override(kind: nil, command: "make run", port: 9000), forPath: OverrideStore.key(directory: dir, kind: .frontend))
        let target = ProjectScanner(overrides: store).scan(root: t.root)[0].targets[0]
        #expect(target.command == "make run")
        #expect(target.port == 9000)
    }

    @Test func overrideCanChangeRole() {
        let t = TempTree()
        t.write("P/package.json", TempTree.viteApp)
        let store = OverrideStore(fileURL: t.root.appendingPathComponent("o.json"))
        store.set(Override(kind: .backend, command: nil, port: nil), forPath: OverrideStore.key(directory: t.root.appendingPathComponent("P"), kind: .frontend))
        #expect(ProjectScanner(overrides: store).scan(root: t.root)[0].targets[0].kind == .backend)
    }
}

@Suite struct OverrideEditTests {
    @Test func customCommandSurvivesLaterPortEdit() {
        let o = Override.edited(command: "npm run dev:local", port: "9000", defaultCommand: "npm run dev")
        #expect(o == Override(command: "npm run dev:local", port: 9000))
    }
    @Test func matchingDefaultAndNoPortClearsOverride() {
        #expect(Override.edited(command: "npm run dev", port: "", defaultCommand: "npm run dev") == nil)
        #expect(Override.edited(command: "  ", port: "abc", defaultCommand: "npm run dev") == nil)
    }
    @Test func portOnlyOverrideKeepsDefaultCommand() {
        #expect(Override.edited(command: "npm run dev", port: "3000", defaultCommand: "npm run dev") == Override(command: nil, port: 3000))
    }
}
