import Foundation

public struct ProjectScanner: Sendable {
    public static let defaultSkips: Set<String> = [
        "node_modules", ".git", "build", "dist", ".next", ".dart_tool",
        "venv", ".venv", "NexLauncher", "__pycache__", "Pods", ".gradle",
    ]
    static let maxDepth = 2

    private let skipNames: Set<String>

    public init(skipNames: Set<String> = ProjectScanner.defaultSkips) {
        self.skipNames = skipNames
    }

    public func scan(root: URL) -> [Project] {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        var projects: [Project] = []
        for child in children.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
            guard isDirectory(child), !skipNames.contains(child.lastPathComponent) else { continue }
            var visited = Set<String>()
            var targets: [ServiceTarget] = []
            collect(in: child, depth: 0, visited: &visited, into: &targets)
            guard !targets.isEmpty else { continue }
            projects.append(Project(id: child.path, name: child.lastPathComponent, root: child, targets: targets))
        }
        return projects
    }

    // MARK: - Walking

    private func collect(in dir: URL, depth: Int, visited: inout Set<String>, into targets: inout [ServiceTarget]) {
        let real = dir.resolvingSymlinksInPath().path
        guard visited.insert(real).inserted else { return }

        let found = Self.detect(in: dir)
        targets.append(contentsOf: found)
        // A directory that is itself a runnable target is a leaf: don't hunt for nested apps inside it.
        guard found.isEmpty, depth < Self.maxDepth else { return }

        let children = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where isDirectory(child) && !skipNames.contains(child.lastPathComponent) {
            collect(in: child, depth: depth + 1, visited: &visited, into: &targets)
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    // MARK: - Manifest detection

    static func detect(in dir: URL) -> [ServiceTarget] {
        let fm = FileManager.default
        func exists(_ name: String) -> Bool { fm.fileExists(atPath: dir.appendingPathComponent(name).path) }
        func text(_ name: String) -> String? { try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) }
        var out: [ServiceTarget] = []
        func add(_ kind: ServiceKind, _ framework: String?) {
            out.append(ServiceTarget(kind: kind, directory: dir, framework: framework, command: ""))
        }

        if let pkg = text("package.json"), let node = nodeKind(pkg) { add(node.kind, node.framework) }
        if exists("manage.py") {
            add(.backend, "Django")
        } else if let req = text("requirements.txt")?.lowercased() {
            if req.contains("fastapi") { add(.backend, "FastAPI") } else if req.contains("flask") { add(.backend, "Flask") }
        }
        if let pub = text("pubspec.yaml"), pub.contains("flutter:") { add(.flutter, "Flutter") }
        if ["docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"].contains(where: exists) { add(.docker, "Docker") }
        return out
    }

    private static let frontendFrameworks: [(dep: String, name: String)] = [
        ("next", "Next.js"), ("nuxt", "Nuxt"), ("react-scripts", "Create React App"), ("vite", "Vite"),
        ("@angular/core", "Angular"), ("svelte", "Svelte"), ("vue", "Vue"), ("react", "React"),
    ]
    private static let backendDeps = ["express", "@nestjs/core", "fastify", "koa", "@hapi/hapi"]

    static func nodeKind(_ json: String) -> (kind: ServiceKind, framework: String?)? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let scripts = obj["scripts"] as? [String: Any] ?? [:]
        guard scripts["dev"] != nil || scripts["start"] != nil else { return nil }
        let deps = Set(((obj["dependencies"] as? [String: Any]) ?? [:]).keys)
            .union(((obj["devDependencies"] as? [String: Any]) ?? [:]).keys)
        if let fw = frontendFrameworks.first(where: { deps.contains($0.dep) }) { return (.frontend, fw.name) }
        if let be = backendDeps.first(where: { deps.contains($0) }) { return (.backend, be == "@nestjs/core" ? "NestJS" : be.capitalized) }
        return (.frontend, nil)
    }
}
