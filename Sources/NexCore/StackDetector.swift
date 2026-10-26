import Foundation

/// One runnable thing found in a folder: what it is, how to run it, and how to set it up.
public struct DetectedStack: Equatable, Sendable {
    public let kind: ServiceKind
    public let framework: String
    /// Shell command to run from the folder (no `cd`).
    public let run: String
    /// Shell command that installs dependencies, if the stack has a setup step.
    public let install: String?
    /// A folder or file whose absence means `install` hasn't been run yet.
    public let installMarker: String?

    public init(kind: ServiceKind, framework: String, run: String, install: String? = nil, installMarker: String? = nil) {
        self.kind = kind
        self.framework = framework
        self.run = run
        self.install = install
        self.installMarker = installMarker
    }
}

/// Recognises projects by their manifests, across stacks. Foundation only (the widget compiles it too).
public enum StackDetector {
    /// `allowFallbacks` covers the guess-work rules (static site, Makefile, Procfile); they only make sense at a
    /// project's own folder, not in sub-folders such as Flutter's `web/`.
    public static func detect(in dir: URL, allowFallbacks: Bool = true) -> [DetectedStack] {
        let files = Files(dir)
        var out: [DetectedStack] = []
        out += node(files)
        out += deno(files)
        out += python(files)
        out += ruby(files)
        out += php(files)
        out += go(files)
        out += rust(files)
        out += java(files)
        out += dotnet(files)
        out += elixir(files)
        out += swift(files)
        out += dart(files)
        // Fallbacks only when nothing more specific was found.
        if out.isEmpty && allowFallbacks { out += fallback(files) }
        out += docker(files)
        return out
    }

    // MARK: - File access

    struct Files {
        let dir: URL
        init(_ dir: URL) { self.dir = dir }
        func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path) }
        func text(_ name: String) -> String? { try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) }
        func json(_ name: String) -> [String: Any]? {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        var names: [String] { (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] }
    }

    // MARK: - Node

    private static let frontendFrameworks: [(dep: String, name: String)] = [
        ("expo", "Expo"), ("next", "Next.js"), ("nuxt", "Nuxt"), ("@remix-run/react", "Remix"), ("astro", "Astro"),
        ("gatsby", "Gatsby"), ("react-scripts", "Create React App"), ("vite", "Vite"), ("@angular/core", "Angular"),
        ("svelte", "Svelte"), ("vue", "Vue"), ("react", "React"),
    ]
    private static let backendFrameworks: [(dep: String, name: String)] = [
        ("@nestjs/core", "NestJS"), ("express", "Express"), ("fastify", "Fastify"), ("koa", "Koa"), ("@hapi/hapi", "Hapi"), ("hono", "Hono"),
    ]

    static func packageManager(_ f: Files) -> String {
        if f.exists("bun.lockb") || f.exists("bun.lock") { return "bun" }
        if f.exists("pnpm-lock.yaml") { return "pnpm" }
        if f.exists("yarn.lock") { return "yarn" }
        return "npm"
    }

    private static let lockfiles = ["bun.lockb", "bun.lock", "pnpm-lock.yaml", "yarn.lock", "package-lock.json"]

    /// The JS workspace root above `dir` (a folder with a lockfile, pnpm-workspace.yaml or "workspaces"), up to
    /// three levels up. Monorepo packages install and resolve from there.
    static func nodeWorkspaceRoot(above dir: URL) -> URL? {
        if lockfiles.contains(where: { Files(dir).exists($0) }) { return nil }
        var current = dir.deletingLastPathComponent()
        for _ in 0..<3 {
            let f = Files(current)
            let declaresWorkspaces = f.exists("pnpm-workspace.yaml") || (f.json("package.json")?["workspaces"] != nil)
            if declaresWorkspaces || lockfiles.contains(where: f.exists) { return current }
            if current.path == "/" || current.path == AppSettings.realHome.path { break }
            current = current.deletingLastPathComponent()
        }
        return nil
    }

    /// Relative path from `dir` up to `root` (e.g. "../..").
    static func relativeUp(from dir: URL, to root: URL) -> String {
        let depth = dir.standardizedFileURL.pathComponents.count - root.standardizedFileURL.pathComponents.count
        return Array(repeating: "..", count: max(depth, 0)).joined(separator: "/")
    }

    private static func node(_ f: Files) -> [DetectedStack] {
        guard let pkg = f.json("package.json") else { return [] }
        let scripts = pkg["scripts"] as? [String: Any] ?? [:]
        let deps = Set(((pkg["dependencies"] as? [String: Any]) ?? [:]).keys)
            .union(((pkg["devDependencies"] as? [String: Any]) ?? [:]).keys)
        let workspace = nodeWorkspaceRoot(above: f.dir)
        let pm = packageManager(workspace.map(Files.init) ?? f)
        let install = workspace.map { "cd \(CommandBuilder.quote($0.path)) && \(pm) install" } ?? "\(pm) install"
        let marker = workspace.map { relativeUp(from: f.dir, to: $0) + "/node_modules" } ?? "node_modules"
        let front = frontendFrameworks.first { deps.contains($0.dep) }
        let back = backendFrameworks.first { deps.contains($0.dep) }

        let run: String
        if scripts["dev"] != nil {
            run = "\(pm) run dev"
        } else if scripts["start"] != nil {
            run = pm == "bun" ? "bun run start" : "\(pm) start"
        } else if scripts["serve"] != nil {
            run = "\(pm) run serve"
        } else if let entry = [pkg["main"] as? String, "server.js", "index.js", "app.js"].compactMap({ $0 }).first(where: f.exists) {
            run = "node \(entry)"
        } else {
            return []
        }
        if let front { return [DetectedStack(kind: .frontend, framework: front.name, run: run, install: install, installMarker: marker)] }
        if let back { return [DetectedStack(kind: .backend, framework: back.name, run: run, install: install, installMarker: marker)] }
        let kind: ServiceKind = run.hasPrefix("node ") ? .backend : .frontend
        return [DetectedStack(kind: kind, framework: "Node", run: run, install: install, installMarker: marker)]
    }

    private static func deno(_ f: Files) -> [DetectedStack] {
        guard let config = f.json("deno.json") ?? f.json("deno.jsonc") ?? (f.exists("deno.json") || f.exists("deno.jsonc") ? [:] : nil) else { return [] }
        let tasks = config["tasks"] as? [String: Any] ?? [:]
        if let task = ["dev", "start"].first(where: { tasks[$0] != nil }) {
            return [DetectedStack(kind: .app, framework: "Deno", run: "deno task \(task)")]
        }
        if let entry = ["main.ts", "mod.ts", "server.ts"].first(where: f.exists) {
            return [DetectedStack(kind: .app, framework: "Deno", run: "deno run -A \(entry)")]
        }
        return []
    }

    // MARK: - Python

    private static func python(_ f: Files) -> [DetectedStack] {
        let requirements = f.text("requirements.txt")
        let pyproject = f.text("pyproject.toml")
        let hasManage = f.exists("manage.py")
        guard hasManage || requirements != nil || pyproject != nil else { return [] }
        let deps = ((requirements ?? "") + "\n" + (pyproject ?? "")).lowercased()

        let usesUV = f.exists("uv.lock")
        let usesPoetry = f.exists("poetry.lock") || (pyproject ?? "").contains("[tool.poetry]")
        let python: String
        if let venv = [".venv/bin/python", "venv/bin/python"].first(where: f.exists) { python = venv }
        else if usesUV { python = "uv run python" }
        else if usesPoetry { python = "poetry run python" }
        else { python = "python3" }

        let install: String?, marker: String?
        if usesUV { install = "uv sync"; marker = ".venv" }
        else if usesPoetry { install = "poetry install"; marker = nil }
        else if requirements != nil { install = "python3 -m venv .venv && .venv/bin/python -m pip install -r requirements.txt"; marker = ".venv" }
        else if pyproject != nil { install = "python3 -m venv .venv && .venv/bin/python -m pip install -e ."; marker = ".venv" }
        else { install = nil; marker = nil }

        func stack(_ kind: ServiceKind, _ name: String, _ run: String) -> [DetectedStack] {
            [DetectedStack(kind: kind, framework: name, run: run, install: install, installMarker: marker)]
        }
        if hasManage { return stack(.backend, "Django", "\(python) manage.py runserver") }
        if deps.contains("fastapi") {
            let module = f.exists("main.py") ? "main" : f.exists("app/main.py") ? "app.main" : f.exists("app.py") ? "app" : "main"
            return stack(.backend, "FastAPI", "\(python) -m uvicorn \(module):app --reload")
        }
        if deps.contains("flask") {
            let module = f.exists("app.py") ? "app" : f.exists("main.py") ? "main" : "app"
            return stack(.backend, "Flask", "\(python) -m flask --app \(module) run")
        }
        if deps.contains("streamlit"), let entry = ["streamlit_app.py", "app.py", "main.py"].first(where: f.exists) {
            return stack(.frontend, "Streamlit", "\(python) -m streamlit run \(entry)")
        }
        if let entry = ["main.py", "app.py", "run.py", "bot.py"].first(where: f.exists) {
            return stack(.app, "Python", "\(python) \(entry)")
        }
        return []
    }

    // MARK: - Other back ends

    private static func ruby(_ f: Files) -> [DetectedStack] {
        guard f.exists("Gemfile") else { return [] }
        if f.exists("config/application.rb") {
            return [DetectedStack(kind: .backend, framework: "Rails", run: f.exists("bin/rails") ? "bin/rails server" : "bundle exec rails server", install: "bundle install")]
        }
        if f.exists("config.ru") {
            return [DetectedStack(kind: .backend, framework: "Rack", run: "bundle exec rackup", install: "bundle install")]
        }
        return []
    }

    private static func php(_ f: Files) -> [DetectedStack] {
        let composer = f.exists("composer.json")
        let install = composer ? "composer install" : nil
        let marker = composer ? "vendor" : nil
        if f.exists("artisan") {
            return [DetectedStack(kind: .backend, framework: "Laravel", run: "php artisan serve", install: install, installMarker: marker)]
        }
        if f.exists("index.php") || (composer && f.exists("public/index.php")) {
            let docroot = f.exists("index.php") ? "" : " -t public"
            return [DetectedStack(kind: .backend, framework: "PHP", run: "php -S localhost:8000\(docroot)", install: install, installMarker: marker)]
        }
        return []
    }

    private static func go(_ f: Files) -> [DetectedStack] {
        guard let mod = f.text("go.mod") else { return [] }
        // Run the main package: at the root, or the only one under cmd/ (the usual layout). Libraries aren't runnable.
        func hasMain(_ dir: URL) -> Bool {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            return names.contains { $0.hasSuffix(".go") && !$0.hasSuffix("_test.go")
                && ((try? String(contentsOf: dir.appendingPathComponent($0), encoding: .utf8))?.contains("package main") == true) }
        }
        let run: String
        if hasMain(f.dir) {
            run = "go run ."
        } else if let cmd = ((try? FileManager.default.contentsOfDirectory(atPath: f.dir.appendingPathComponent("cmd").path)) ?? [])
                    .sorted().first(where: { hasMain(f.dir.appendingPathComponent("cmd/\($0)")) }) {
            run = "go run ./cmd/\(cmd)"
        } else {
            return []
        }
        let web: [(String, String)] = [("gin-gonic/gin", "Gin"), ("labstack/echo", "Echo"), ("gofiber/fiber", "Fiber"), ("go-chi/chi", "Chi"), ("gorilla/mux", "Gorilla")]
        if let hit = web.first(where: { mod.contains($0.0) }) {
            return [DetectedStack(kind: .backend, framework: "Go · \(hit.1)", run: run)]
        }
        return [DetectedStack(kind: .app, framework: "Go", run: run)]
    }

    private static func rust(_ f: Files) -> [DetectedStack] {
        guard let cargo = f.text("Cargo.toml") else { return [] }
        let web: [(String, String)] = [("actix-web", "Actix"), ("axum", "Axum"), ("rocket", "Rocket"), ("warp", "Warp")]
        if let hit = web.first(where: { cargo.contains($0.0) }) {
            return [DetectedStack(kind: .backend, framework: "Rust · \(hit.1)", run: "cargo run")]
        }
        return [DetectedStack(kind: .app, framework: "Rust", run: "cargo run")]
    }

    private static func java(_ f: Files) -> [DetectedStack] {
        if let pom = f.text("pom.xml"), pom.contains("spring-boot") {
            return [DetectedStack(kind: .backend, framework: "Spring Boot", run: f.exists("mvnw") ? "./mvnw spring-boot:run" : "mvn spring-boot:run")]
        }
        if let gradle = f.text("build.gradle") ?? f.text("build.gradle.kts"), gradle.contains("org.springframework.boot") {
            return [DetectedStack(kind: .backend, framework: "Spring Boot", run: f.exists("gradlew") ? "./gradlew bootRun" : "gradle bootRun")]
        }
        return []
    }

    private static func dotnet(_ f: Files) -> [DetectedStack] {
        guard let proj = f.names.first(where: { $0.hasSuffix(".csproj") || $0.hasSuffix(".fsproj") }) else { return [] }
        let web = f.text(proj)?.contains("Microsoft.NET.Sdk.Web") == true
        return [DetectedStack(kind: web ? .backend : .app, framework: web ? "ASP.NET" : ".NET", run: "dotnet run",
                              install: "dotnet restore", installMarker: "obj")]
    }

    private static func elixir(_ f: Files) -> [DetectedStack] {
        guard let mix = f.text("mix.exs") else { return [] }
        if mix.contains(":phoenix") {
            return [DetectedStack(kind: .backend, framework: "Phoenix", run: "mix phx.server", install: "mix deps.get", installMarker: "deps")]
        }
        return [DetectedStack(kind: .app, framework: "Elixir", run: "mix run --no-halt", install: "mix deps.get", installMarker: "deps")]
    }

    private static func swift(_ f: Files) -> [DetectedStack] {
        guard let manifest = f.text("Package.swift"), manifest.contains("executableTarget") || manifest.contains(".executable(") else { return [] }
        return [DetectedStack(kind: .app, framework: "Swift", run: "swift run")]
    }

    private static func dart(_ f: Files) -> [DetectedStack] {
        guard let pub = f.text("pubspec.yaml") else { return [] }
        if pub.contains("flutter:") {
            return [DetectedStack(kind: .flutter, framework: "Flutter", run: "flutter run", install: "flutter pub get", installMarker: ".dart_tool")]
        }
        guard f.exists("bin") || f.exists("lib/main.dart") else { return [] }
        return [DetectedStack(kind: .app, framework: "Dart", run: "dart run", install: "dart pub get", installMarker: ".dart_tool")]
    }

    private static func docker(_ f: Files) -> [DetectedStack] {
        guard ["docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"].contains(where: f.exists) else { return [] }
        return [DetectedStack(kind: .docker, framework: "Docker", run: "docker compose up")]
    }

    // MARK: - Fallbacks

    private static func fallback(_ f: Files) -> [DetectedStack] {
        if let procfile = f.text("Procfile"),
           let web = procfile.split(separator: "\n").first(where: { $0.hasPrefix("web:") }) {
            let command = web.dropFirst(4).trimmingCharacters(in: .whitespaces)
            if !command.isEmpty { return [DetectedStack(kind: .backend, framework: "Procfile", run: command)] }
        }
        if let makefile = f.text("Makefile") ?? f.text("makefile") {
            let targets = Set(makefile.split(separator: "\n").compactMap { line -> String? in
                guard let colon = line.firstIndex(of: ":"), !line.hasPrefix("\t"), !line.hasPrefix(" ") else { return nil }
                return String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            })
            if let target = ["dev", "start", "serve", "run"].first(where: targets.contains) {
                return [DetectedStack(kind: .app, framework: "Make", run: "make \(target)")]
            }
        }
        if f.exists("index.html") {
            return [DetectedStack(kind: .frontend, framework: "Static site", run: "python3 -m http.server 8000")]
        }
        return []
    }
}
