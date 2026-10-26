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
        scanTree(root: root, cache: ScanCache())
    }

    /// Test hook: the same scan, also reporting the most times any single folder was inspected.
    func scanTreeMeasured(root: URL) -> (nodes: [ProjectNode], maxDetectionsPerFolder: Int) {
        let cache = ScanCache()
        let nodes = scanTree(root: root, cache: cache)
        return (nodes, cache.detectCounts.values.max() ?? 0)
    }

    private func scanTree(root: URL, cache: ScanCache) -> [ProjectNode] {
        subdirectories(of: root, cache: cache).compactMap { node(for: $0, depth: 1, cache: cache) }
    }

    // MARK: - Tree building

    /// Memoises per-scan work so no folder is listed or inspected more than once.
    final class ScanCache {
        var subdirs: [String: [URL]] = [:]
        var detected: [String: [ServiceTarget]] = [:]
        var collected: [String: Collected] = [:]
        var detectCounts: [String: Int] = [:]
    }

    struct Collected {
        let targets: [ServiceTarget]
        let nested: [(url: URL, depth: Int)]
    }

    private func detectedTargets(in dir: URL, cache: ScanCache, allowFallbacks: Bool = true) -> [ServiceTarget] {
        let key = dir.path + (allowFallbacks ? "" : "#strict")
        if let hit = cache.detected[key] { return hit }
        cache.detectCounts[key, default: 0] += 1
        let found = Self.detect(in: dir, allowFallbacks: allowFallbacks).map(finalize)
        cache.detected[key] = found
        return found
    }

    private func node(for dir: URL, depth: Int, cache: ScanCache) -> ProjectNode? {
        if detectedTargets(in: dir, cache: cache).isEmpty, depth < Self.maxTreeDepth {
            // A slot counts if it holds manifests or nested repositories that do.
            let slots = subdirectories(of: dir, cache: cache).filter {
                let found = collectTargets(in: $0, depth: depth + 1, cache: cache)
                return !found.targets.isEmpty || !found.nested.isEmpty
            }
            if slots.count >= 2 {
                let kinds = Set(slots.flatMap { collectTargets(in: $0, depth: depth + 1, cache: cache).targets.map(\.kind) })
                if !(kinds.contains(.frontend) && kinds.contains(.backend)) {
                    let children = slots.compactMap { node(for: $0, depth: depth + 1, cache: cache) }
                    if children.count >= 2 {
                        return ProjectNode(id: dir.path, name: dir.lastPathComponent, url: dir, kind: .collection, project: nil, children: children)
                    }
                }
            }
        }
        let (targets, nested) = { let c = collectTargets(in: dir, depth: depth, cache: cache); return (c.targets, c.nested) }()
        if targets.isEmpty {
            // No manifests of its own: the apps live in nested repositories (e.g. frontend/ and backend/ as separate repos).
            let childNodes = nested.compactMap { node(for: $0.url, depth: $0.depth, cache: cache) }
            let apps = childNodes.flatMap(\.apps)
            guard !apps.isEmpty else { return nil }
            let kinds = Set(apps.flatMap { $0.targets.map(\.kind) })
            if childNodes.count >= 2 && !(kinds.contains(.frontend) && kinds.contains(.backend)) {
                return ProjectNode(id: dir.path, name: dir.lastPathComponent, url: dir, kind: .collection, project: nil, children: childNodes)
            }
            let project = Project(id: dir.path, name: dir.lastPathComponent, root: dir, targets: apps.flatMap(\.targets))
            return ProjectNode(id: dir.path, name: dir.lastPathComponent, url: dir, kind: .app, project: project, children: [])
        }
        let project = Project(id: dir.path, name: dir.lastPathComponent, root: dir, targets: targets)
        let children = nested.compactMap { node(for: $0.url, depth: $0.depth, cache: cache) }
        return ProjectNode(id: dir.path, name: dir.lastPathComponent, url: dir, kind: .app, project: project, children: children)
    }

    /// Targets in `dir` and up to two levels below it. Nested git repositories are returned separately.
    private func collectTargets(in dir: URL, depth: Int, cache: ScanCache) -> Collected {
        let key = "\(dir.path)#\(depth)"
        if let hit = cache.collected[key] { return hit }
        var targets: [ServiceTarget] = []
        var nested: [(url: URL, depth: Int)] = []
        func walk(_ d: URL, rel: Int, abs: Int) {
            let found = detectedTargets(in: d, cache: cache, allowFallbacks: rel == 0)
            targets.append(contentsOf: found)
            // A sub-folder that is itself a target is a leaf; the app's own root keeps looking for siblings.
            guard rel < Self.maxDepth, abs < Self.maxTreeDepth, rel == 0 || found.isEmpty else { return }
            for sub in subdirectories(of: d, cache: cache) {
                if FileManager.default.fileExists(atPath: sub.appendingPathComponent(".git").path) {
                    nested.append((sub, abs + 1))
                    continue
                }
                walk(sub, rel: rel + 1, abs: abs + 1)
            }
        }
        walk(dir, rel: 0, abs: depth)
        let result = Collected(targets: targets, nested: nested)
        cache.collected[key] = result
        return result
    }

    /// Visible sub-folders, skipping the skip-list and symlinks (so loops cannot occur), sorted by name.
    private func subdirectories(of dir: URL, cache: ScanCache) -> [URL] {
        if let hit = cache.subdirs[dir.path] { return hit }
        let kids = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])) ?? []
        let result = kids.filter { url in
            guard !skipNames.contains(url.lastPathComponent),
                  let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
            return v.isDirectory == true && v.isSymbolicLink != true
        }.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        cache.subdirs[dir.path] = result
        return result
    }

    /// Fills the default command, then applies any user override keyed by `"<dir>|<detected kind>"`.
    private func finalize(_ detected: ServiceTarget) -> ServiceTarget {
        var target = detected
        if target.command.isEmpty {
            target.command = CommandBuilder.command(for: detected.kind, at: detected.directory, framework: detected.framework, flutterDevice: "macos")
        }
        guard let o = overrides?.override(forPath: OverrideStore.key(directory: detected.directory, kind: detected.kind)) else { return target }
        let kind = o.kind ?? detected.kind
        if let cmd = o.command { target.command = cmd } else if kind != detected.kind {
            target.command = CommandBuilder.command(for: kind, at: detected.directory, framework: detected.framework, flutterDevice: "macos")
        }
        target.port = o.port
        return ServiceTarget(kind: kind, directory: target.directory, framework: target.framework, command: target.command, port: target.port)
    }

    // MARK: - Manifest detection

    static func detect(in dir: URL, allowFallbacks: Bool = true) -> [ServiceTarget] {
        StackDetector.detect(in: dir, allowFallbacks: allowFallbacks).map { stack in
            let body = stack.kind == .flutter ? stack.run + " -d macos" : stack.run
            return ServiceTarget(kind: stack.kind, directory: dir, framework: stack.framework,
                                 command: "cd \(CommandBuilder.quote(dir.path)) && \(body)")
        }
    }
}
