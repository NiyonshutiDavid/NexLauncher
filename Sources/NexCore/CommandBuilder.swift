import Foundation

public enum CommandBuilder {
    /// Single-quotes a string for safe use in a POSIX shell.
    public static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Quotes only when needed, so common values like `macos` stay readable.
    static func quoteIfNeeded(_ s: String) -> String {
        s.range(of: "^[A-Za-z0-9._:@/=+-]+$", options: .regularExpression) != nil ? s : quote(s)
    }

    public static func command(for kind: ServiceKind, at directory: URL, framework: String?, flutterDevice: String?) -> String {
        "cd \(quote(directory.path)) && " + body(for: kind, at: directory, framework: framework, flutterDevice: flutterDevice)
    }

    /// The stack in `directory` that a target of this kind (and framework, if known) refers to.
    static func stack(for kind: ServiceKind, at directory: URL, framework: String?) -> DetectedStack? {
        let stacks = StackDetector.detect(in: directory).filter { $0.kind == kind }
        return stacks.first { $0.framework == framework } ?? stacks.first
    }

    private static func body(for kind: ServiceKind, at dir: URL, framework: String?, flutterDevice: String?) -> String {
        let device = flutterDevice.map { " -d \(quoteIfNeeded($0))" } ?? ""
        if let found = stack(for: kind, at: dir, framework: framework) {
            return kind == .flutter ? found.run + device : found.run
        }
        // Nothing on disk matches (e.g. a role override): sensible defaults per kind.
        switch kind {
        case .flutter: return "flutter run" + device
        case .docker: return "docker compose up"
        case .frontend, .backend, .app:
            let python = ["venv", ".venv"].map { "\($0)/bin/python" }
                .first { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) } ?? "python3"
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("package.json").path) { return "npm run dev" }
            if framework == "FastAPI" { return "\(python) -m uvicorn main:app --reload" }
            return "\(python) manage.py runserver"
        }
    }

    /// True when the target's stack has a setup step whose marker (e.g. node_modules, .venv, vendor) is missing.
    public static func needsInstall(_ target: ServiceTarget) -> Bool {
        guard let found = stack(for: target.kind, at: target.directory, framework: target.framework),
              found.install != nil, let marker = found.installMarker else { return false }
        let fm = FileManager.default
        let markers = marker == ".venv" ? [".venv", "venv"] : [marker]
        return !markers.contains { fm.fileExists(atPath: target.directory.appendingPathComponent($0).path) }
    }

    /// The setup command without the leading `cd` (for display).
    public static func installBody(for target: ServiceTarget) -> String {
        stack(for: target.kind, at: target.directory, framework: target.framework)?.install ?? "npm install"
    }

    public static func installCommand(for target: ServiceTarget) -> String {
        let install = stack(for: target.kind, at: target.directory, framework: target.framework)?.install ?? "npm install"
        return "cd \(quote(target.directory.path)) && \(install)"
    }
}
