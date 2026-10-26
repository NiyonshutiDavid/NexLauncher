import Foundation

public struct Override: Codable, Equatable, Sendable {
    public var kind: ServiceKind?
    public var command: String?
    public var port: Int?

    public init(kind: ServiceKind? = nil, command: String? = nil, port: Int? = nil) {
        self.kind = kind
        self.command = command
        self.port = port
    }
}

/// Persists per-service overrides as JSON, keyed by `"<directory path>|<detected kind>"`.
public final class OverrideStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private var values: [String: Override]

    public init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: Override].self, from: data) {
            values = decoded
        } else {
            values = [:]
        }
    }

    /// Canonical key for a detected service; symlinks are resolved so /var and /private/var agree.
    public static func key(directory: URL, kind: ServiceKind) -> String {
        "\(directory.resolvingSymlinksInPath().path)|\(kind.rawValue)"
    }

    public func override(forPath path: String) -> Override? {
        lock.lock(); defer { lock.unlock() }
        return values[path]
    }

    public func set(_ value: Override?, forPath path: String) {
        lock.lock(); defer { lock.unlock() }
        values[path] = value
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(values) { try? data.write(to: fileURL, options: .atomic) }
    }
}
