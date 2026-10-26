import Foundation

public struct ProjectScanner: Sendable {
    public static let defaultSkips: Set<String> = [
        "node_modules", ".git", "build", "dist", ".next", ".dart_tool",
        "venv", ".venv", "NexLauncher", "__pycache__", "Pods", ".gradle",
    ]
    /// How many levels below an app's own folder are searched for manifests.
    static let maxDepth = 2
    /// How deep below the scan root folders are considered at all.
    static let maxTreeDepth = 4

    private let skipNames: Set<String>
    private let overrides: OverrideStore?

    public init(skipNames: Set<String> = ProjectScanner.defaultSkips, overrides: OverrideStore? = nil) {
        self.skipNames = skipNames
        self.overrides = overrides
    }

    /// Every runnable app under `root`, flattened (collections and nested apps included).
    public func scan(root: URL) -> [Project] {
        scanTree(root: root).flatMap(\.apps)
    }

    /// The project tree under `root`. Rules for a folder F:
    ///  1. F has manifests of its own → an app (its subfolders' targets join it, except nested repos, which become children).
    ///  2. Otherwise, if two or more subfolders hold apps and they are not a frontend+backend pair → a collection
    ///     whose children are those subfolders, evaluated recursively.
    ///  3. Otherwise the targets found below F make one app (or nothing).
    public func scanTree(root: URL) -> [ProjectNode] {
        subdirectories(of: root)
            .compactMap { node(for: $0, depth: 1) }
    }

    // MARK: - Tree building

    private func node(for dir: URL, depth: Int) -> ProjectNode? {
        if Self.detect(in: dir).isEmpty, depth < Self.maxTreeDepth {
            let slots = subdirectories(of: dir).filter { !collectTargets(in: $0, depth: depth + 1).targets.isEmpty }
            if slots.count >= 2 {
                let kinds = Set(slots.flatMap { collectTargets(in: $0, depth: depth + 1).targets.map(\.kind) })
                if !(kinds.contains(.frontend) && kinds.contains(.backend)) {
                    let children = slots.compactMap { node(for: $0, depth: depth + 1) }
                    if children.count >= 2 {
                        return ProjectNode(id: dir.path, name: dir.lastPathComponent, url: dir, kind: .collection, project: nil, children: children)
                    }
                }
            }
        }
        let (targets, nested) = collectTargets(in: dir, depth: depth)
        guard !targets.isEmpty else { return nil }
        let project = Project(id: dir.path, name: dir.lastPathComponent, root: dir, targets: targets)
        let children = nested.compactMap { node(for: $0.url, depth: $0.depth) }
        return ProjectNode(id: dir.path, name: dir.lastPathComponent, url: dir, kind: .app, project: project, children: children)
    }

    /// Targets in `dir` and up to two levels below it. Nested git repositories are returned separately.
    private func collectTargets(in dir: URL, depth: Int) -> (targets: [ServiceTarget], nested: [(url: URL, depth: Int)]) {
        var targets: [ServiceTarget] = []
        var nested: [(url: URL, depth: Int)] = []
        func walk(_ d: URL, rel: Int, abs: Int) {
            let found = Self.detect(in: d).map(finalize)
            targets.append(contentsOf: found)
            // A sub-folder that is itself a target is a leaf; the app's own root keeps looking for siblings.
            guard rel < Self.maxDepth, abs < Self.maxTreeDepth, rel == 0 || found.isEmpty else { return }
            for sub in subdirectories(of: d) {
                if FileManager.default.fileExists(atPath: sub.appendingPathComponent(".git").path) {
                    nested.append((sub, abs + 1))
                    continue
                }
                walk(sub, rel: rel + 1, abs: abs + 1)
            }
        }
        walk(dir, rel: 0, abs: depth)
        return (targets, nested)
    }

    /// Visible sub-folders, skipping the skip-list and symlinks (so loops cannot occur), sorted by name.
    private func subdirectories(of dir: URL) -> [URL] {
        let kids = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])) ?? []
        return kids.filter { url in
            guard !skipNames.contains(url.lastPathComponent),
                  let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
            return v.isDirectory == true && v.isSymbolicLink != true
        }.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Fills the default command, then applies any user override keyed by `"<dir>|<detected kind>"`.
    private func finalize(_ detected: ServiceTarget) -> ServiceTarget {
        var target = detected
        target.command = CommandBuilder.command(for: detected.kind, at: detected.directory, framework: detected.framework, flutterDevice: "macos")
        guard let o = overrides?.override(forPath: OverrideStore.key(directory: detected.directory, kind: detected.kind)) else { return target }
        let kind = o.kind ?? detected.kind
        if let cmd = o.command { target.command = cmd } else if kind != detected.kind {
            target.command = CommandBuilder.command(for: kind, at: detected.directory, framework: detected.framework, flutterDevice: "macos")
        }
        target.port = o.port
        return ServiceTarget(kind: kind, directory: target.directory, framework: target.framework, command: target.command, port: target.port)
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
