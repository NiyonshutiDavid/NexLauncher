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

    private static func body(for kind: ServiceKind, at dir: URL, framework: String?, flutterDevice: String?) -> String {
        switch kind {
        case .flutter:
            return "flutter run" + (flutterDevice.map { " -d \(quoteIfNeeded($0))" } ?? "")
        case .docker:
            return "docker compose up"
        case .frontend, .backend:
            let fm = FileManager.default
            let pythonFrameworks: Set<String> = ["Django", "FastAPI", "Flask"]
            if !pythonFrameworks.contains(framework ?? ""), fm.fileExists(atPath: dir.appendingPathComponent("package.json").path) {
                return hasScript("dev", in: dir) ? "npm run dev" : "npm start"
            }
            let python = ["venv", ".venv"].map { "\($0)/bin/python" }
                .first { fm.fileExists(atPath: dir.appendingPathComponent($0).path) } ?? "python3"
            if framework == "FastAPI" { return "\(python) -m uvicorn main:app --reload" }
            if framework == "Flask" { return "\(python) -m flask run" }
            return "\(python) manage.py runserver"
        }
    }

    private static func hasScript(_ name: String, in dir: URL) -> Bool {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("package.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = obj["scripts"] as? [String: Any] else { return false }
        return scripts[name] != nil
    }

    public static func needsInstall(_ target: ServiceTarget) -> Bool {
        let fm = FileManager.default
        guard target.kind == .frontend || target.kind == .backend,
              fm.fileExists(atPath: target.directory.appendingPathComponent("package.json").path) else { return false }
        return !fm.fileExists(atPath: target.directory.appendingPathComponent("node_modules").path)
    }

    public static func installCommand(for target: ServiceTarget) -> String {
        "cd \(quote(target.directory.path)) && npm install"
    }
}
