import Testing
import Foundation
@testable import NexCore

@Suite struct StackDetectorTests {
    private func detect(_ t: TempTree, _ dir: String) -> [DetectedStack] {
        StackDetector.detect(in: t.root.appendingPathComponent(dir))
    }
    private func one(_ t: TempTree, _ dir: String) -> DetectedStack? {
        let all = detect(t, dir)
        #expect(all.count == 1, "expected one stack in \(dir), got \(all.map(\.framework))")
        return all.first
    }

    // MARK: Node family

    @Test(arguments: [("pnpm-lock.yaml", "pnpm"), ("yarn.lock", "yarn"), ("bun.lockb", "bun"), ("bun.lock", "bun"), ("package-lock.json", "npm")])
    func packageManagerComesFromTheLockfile(lock: String, pm: String) {
        let t = TempTree()
        t.write("w/package.json", TempTree.viteApp); t.write("w/\(lock)", "")
        let s = one(t, "w")
        #expect(s?.run == "\(pm) run dev")
        #expect(s?.install == "\(pm) install")
        #expect(s?.installMarker == "node_modules")
    }

    @Test func expoIsAFrontendThatStartsExpo() {
        let t = TempTree()
        t.write("m/package.json", #"{"scripts":{"start":"expo start"},"dependencies":{"expo":"51","react-native":"0.74"}}"#)
        let s = one(t, "m")
        #expect(s?.kind == .frontend && s?.framework == "Expo" && s?.run == "npm start")
    }

    @Test func nodeServerWithoutScriptsRunsItsEntryFile() {
        let t = TempTree()
        t.write("api/package.json", #"{"name":"api","main":"server.js","dependencies":{"express":"4"}}"#)
        t.write("api/server.js", "")
        let s = one(t, "api")
        #expect(s?.kind == .backend && s?.run == "node server.js")
    }

    @Test func denoTaskRuns() {
        let t = TempTree()
        t.write("d/deno.json", #"{"tasks":{"dev":"deno run -A main.ts"}}"#)
        #expect(one(t, "d")?.run == "deno task dev")
    }

    // MARK: Python

    @Test func streamlitAppRuns() {
        let t = TempTree()
        t.write("s/requirements.txt", "streamlit\npandas\n"); t.write("s/app.py", "")
        let s = one(t, "s")
        #expect(s?.framework == "Streamlit" && s?.kind == .frontend)
        #expect(s?.run == "python3 -m streamlit run app.py")
    }

    @Test func fastAPIFindsItsModule() {
        let t = TempTree()
        t.write("f/requirements.txt", "fastapi\nuvicorn\n"); t.mkdir("f/app"); t.write("f/app/main.py", "")
        #expect(one(t, "f")?.run == "python3 -m uvicorn app.main:app --reload")
    }

    @Test func plainPythonScriptIsAnApp() {
        let t = TempTree()
        t.write("bot/requirements.txt", "requests\n"); t.write("bot/main.py", "")
        let s = one(t, "bot")
        #expect(s?.kind == .app && s?.framework == "Python" && s?.run == "python3 main.py")
    }

    @Test func pythonInstallCreatesAVirtualEnvironment() {
        let t = TempTree()
        t.write("api/manage.py"); t.write("api/requirements.txt", "django\n")
        let s = one(t, "api")
        #expect(s?.install == "python3 -m venv .venv && .venv/bin/python -m pip install -r requirements.txt")
        #expect(s?.installMarker == ".venv")
    }

    @Test func uvAndPoetryProjectsRunThroughTheirTool() {
        let t = TempTree()
        t.write("u/pyproject.toml", "[project]\nname='x'\ndependencies=['fastapi']\n"); t.write("u/uv.lock", ""); t.write("u/main.py", "")
        t.write("p/pyproject.toml", "[tool.poetry]\nname='x'\n[tool.poetry.dependencies]\nflask='*'\n"); t.write("p/poetry.lock", ""); t.write("p/app.py", "")
        #expect(one(t, "u")?.run == "uv run python -m uvicorn main:app --reload")
        #expect(one(t, "u")?.install == "uv sync")
        #expect(one(t, "p")?.run == "poetry run python -m flask --app app run")
        #expect(one(t, "p")?.install == "poetry install")
    }

    // MARK: Other back ends

    @Test func railsRunsTheServer() {
        let t = TempTree()
        t.write("r/Gemfile", "gem 'rails'\n"); t.write("r/config/application.rb", ""); t.write("r/bin/rails", "")
        let s = one(t, "r")
        #expect(s?.framework == "Rails" && s?.kind == .backend && s?.run == "bin/rails server")
        #expect(s?.install == "bundle install")
    }

    @Test func laravelUsesArtisanAndComposer() {
        let t = TempTree()
        t.write("l/artisan", ""); t.write("l/composer.json", #"{"require":{"laravel/framework":"^11"}}"#)
        let s = one(t, "l")
        #expect(s?.framework == "Laravel" && s?.run == "php artisan serve")
        #expect(s?.install == "composer install" && s?.installMarker == "vendor")
    }

    @Test func plainPHPUsesTheBuiltInServer() {
        let t = TempTree()
        t.write("site/index.php", "<?php echo 1;")
        #expect(one(t, "site")?.run == "php -S localhost:8000")
    }

    @Test func goWebFrameworkIsABackendAndPlainGoIsAnApp() {
        let t = TempTree()
        t.write("web/go.mod", "module x\nrequire github.com/gin-gonic/gin v1.9.0\n"); t.write("web/main.go", "package main\n")
        t.write("cli/go.mod", "module y\n"); t.write("cli/main.go", "package main\n")
        #expect(one(t, "web")?.kind == .backend && one(t, "web")?.framework == "Go · Gin")
        #expect(one(t, "cli")?.kind == .app && one(t, "cli")?.run == "go run .")
    }

    @Test func rustWebFrameworkIsABackend() {
        let t = TempTree()
        t.write("rs/Cargo.toml", "[package]\nname='x'\n[dependencies]\naxum = \"0.7\"\n")
        let s = one(t, "rs")
        #expect(s?.kind == .backend && s?.framework == "Rust · Axum" && s?.run == "cargo run")
    }

    @Test func springBootPrefersTheWrapper() {
        let t = TempTree()
        t.write("mvn/pom.xml", "<project><parent><artifactId>spring-boot-starter-parent</artifactId></parent></project>"); t.write("mvn/mvnw", "")
        t.write("gr/build.gradle.kts", "plugins { id(\"org.springframework.boot\") version \"3.3.0\" }")
        #expect(one(t, "mvn")?.run == "./mvnw spring-boot:run")
        #expect(one(t, "gr")?.run == "gradle bootRun")
    }

    @Test func dotnetWebProjectRuns() {
        let t = TempTree()
        t.write("api/Api.csproj", "<Project Sdk=\"Microsoft.NET.Sdk.Web\"></Project>")
        let s = one(t, "api")
        #expect(s?.kind == .backend && s?.framework == "ASP.NET" && s?.run == "dotnet run")
    }

    @Test func phoenixRunsTheServer() {
        let t = TempTree()
        t.write("ex/mix.exs", "defp deps do [{:phoenix, \"~> 1.7\"}] end")
        let s = one(t, "ex")
        #expect(s?.framework == "Phoenix" && s?.run == "mix phx.server" && s?.install == "mix deps.get")
    }

    @Test func swiftPackageRuns() {
        let t = TempTree()
        t.write("tool/Package.swift", "// swift-tools-version: 6.0\n.executableTarget(name: \"tool\")")
        #expect(one(t, "tool")?.run == "swift run")
    }

    // MARK: Fallbacks

    @Test func staticSiteIsServedLocally() {
        let t = TempTree()
        t.write("landing/index.html", "<html></html>")
        let s = one(t, "landing")
        #expect(s?.kind == .frontend && s?.framework == "Static site" && s?.run == "python3 -m http.server 8000")
    }

    @Test func makefileTargetIsUsedWhenNothingElseMatches() {
        let t = TempTree()
        t.write("mk/Makefile", "build:\n\techo b\nrun:\n\techo r\n")
        #expect(one(t, "mk")?.run == "make run")
    }

    @Test func procfileWebCommandIsUsed() {
        let t = TempTree()
        t.write("pf/Procfile", "web: gunicorn app:app --bind 0.0.0.0:5000\nworker: celery\n")
        let s = one(t, "pf")
        #expect(s?.kind == .backend && s?.run == "gunicorn app:app --bind 0.0.0.0:5000")
    }

    @Test func flutterInstallsPackagesWhenDartToolIsMissing() {
        let t = TempTree()
        t.write("mob/pubspec.yaml", "dependencies:\n  flutter:\n    sdk: flutter\n")
        let s = one(t, "mob")
        #expect(s?.kind == .flutter && s?.install == "flutter pub get" && s?.installMarker == ".dart_tool")
    }

    @Test func fallbacksDoNotDuplicateARealStack() {
        let t = TempTree()
        t.write("w/package.json", TempTree.viteApp); t.write("w/index.html", ""); t.write("w/Makefile", "run:\n\tx\n")
        #expect(detect(t, "w").map(\.framework) == ["Vite"])
    }

    @Test func emptyFolderHasNoStack() {
        let t = TempTree(); t.mkdir("nothing")
        #expect(detect(t, "nothing").isEmpty)
    }
}

@Suite struct InstallNeedsTests {
    @Test func installIsNeededUntilTheMarkerExists() {
        let t = TempTree()
        t.write("l/artisan", ""); t.write("l/composer.json", #"{"require":{"laravel/framework":"^11"}}"#)
        let target = ProjectScanner().scan(root: t.root)[0].targets[0]
        #expect(CommandBuilder.needsInstall(target))
        #expect(CommandBuilder.installCommand(for: target).hasSuffix("&& composer install"))
        t.mkdir("l/vendor")
        #expect(!CommandBuilder.needsInstall(target))
    }

    @Test func stacksWithoutAnInstallStepNeverAsk() {
        let t = TempTree()
        t.write("cli/go.mod", "module y\n"); t.write("cli/main.go", "package main\n")
        let target = ProjectScanner().scan(root: t.root)[0].targets[0]
        #expect(!CommandBuilder.needsInstall(target))
    }
}

@Suite struct FallbackScopeTests {
    @Test func flutterWebFolderIsNotAStaticSite() {
        let t = TempTree()
        t.write("app/pubspec.yaml", "dependencies:\n  flutter:\n    sdk: flutter\n")
        t.write("app/web/index.html", "<html></html>")
        let project = ProjectScanner().scan(root: t.root)[0]
        #expect(project.targets.map(\.kind) == [.flutter])
    }

    @Test func htmlCopyInsideAViteAppIsIgnored() {
        let t = TempTree()
        t.write("site/package.json", TempTree.viteApp)
        t.write("site/HTML-copy/index.html", "<html></html>")
        #expect(ProjectScanner().scan(root: t.root)[0].targets.map(\.framework) == ["Vite"])
    }

    @Test func aStaticSiteAtTheTopIsStillFound() {
        let t = TempTree()
        t.write("landing/index.html", "<html></html>")
        #expect(ProjectScanner().scan(root: t.root)[0].targets.map(\.framework) == ["Static site"])
    }
}

@Suite struct ReviewFixStackTests {
    @Test func pnpmWorkspaceUsesTheRootLockfileAndInstallsAtTheRoot() {
        let t = TempTree()
        t.write("mono/pnpm-lock.yaml", ""); t.write("mono/pnpm-workspace.yaml", "packages: ['apps/*']")
        t.write("mono/apps/web/package.json", TempTree.viteApp)
        let s = StackDetector.detect(in: t.root.appendingPathComponent("mono/apps/web")).first
        #expect(s?.run == "pnpm run dev")
        #expect(s?.install == "cd \(CommandBuilder.quote(t.root.appendingPathComponent("mono").path)) && pnpm install")
        #expect(s?.installMarker == "../../node_modules")
    }

    @Test func npmWorkspaceIsInstalledOnceAtTheRoot() {
        let t = TempTree()
        t.write("mono/package.json", #"{"private":true,"workspaces":["apps/*"]}"#); t.write("mono/package-lock.json", "")
        t.write("mono/apps/web/package.json", TempTree.viteApp)
        t.mkdir("mono/node_modules")
        let target = ServiceTarget(kind: .frontend, directory: t.root.appendingPathComponent("mono/apps/web"), framework: "Vite", command: "")
        #expect(!CommandBuilder.needsInstall(target))
    }

    @Test func standaloneAppStillUsesItsOwnFolder() {
        let t = TempTree()
        t.write("site/package.json", TempTree.viteApp)
        let s = StackDetector.detect(in: t.root.appendingPathComponent("site")).first
        #expect(s?.install == "npm install" && s?.installMarker == "node_modules")
    }

    @Test func goCmdLayoutRunsTheOnlyCommand() {
        let t = TempTree()
        t.write("svc/go.mod", "module x\n"); t.write("svc/cmd/server/main.go", "package main\nfunc main(){}\n")
        #expect(StackDetector.detect(in: t.root.appendingPathComponent("svc")).first?.run == "go run ./cmd/server")
    }

    @Test func goMainAtTheRootRunsDot() {
        let t = TempTree()
        t.write("cli/go.mod", "module y\n"); t.write("cli/main.go", "package main\nfunc main(){}\n")
        #expect(StackDetector.detect(in: t.root.appendingPathComponent("cli")).first?.run == "go run .")
    }

    @Test func goLibraryWithoutMainIsNotRunnable() {
        let t = TempTree()
        t.write("lib/go.mod", "module z\n"); t.write("lib/util.go", "package util\n")
        #expect(StackDetector.detect(in: t.root.appendingPathComponent("lib")).isEmpty)
    }

    @Test func pyprojectOnlyProjectGetsAVirtualEnvironment() {
        let t = TempTree()
        t.write("api/pyproject.toml", "[project]\nname='api'\ndependencies=['fastapi','uvicorn']\n"); t.write("api/main.py", "")
        let s = StackDetector.detect(in: t.root.appendingPathComponent("api")).first
        #expect(s?.install == "python3 -m venv .venv && .venv/bin/python -m pip install -e .")
        #expect(s?.installMarker == ".venv")
    }
}
