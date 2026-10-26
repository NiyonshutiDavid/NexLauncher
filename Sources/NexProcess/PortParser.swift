import Foundation

public enum PortParser {
    private static let ansi = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]")
    private static let patterns = [
        try! NSRegularExpression(pattern: #"(?:localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1?\]):(\d{2,5})"#),
        try! NSRegularExpression(pattern: #"port\s+(\d{2,5})"#, options: .caseInsensitive),
    ]

    public static func stripANSI(_ line: String) -> String {
        ansi.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line), withTemplate: "")
    }

    public static func port(in line: String) -> Int? {
        let clean = stripANSI(line)
        let range = NSRange(clean.startIndex..., in: clean)
        for re in patterns {
            if let m = re.firstMatch(in: clean, range: range), let r = Range(m.range(at: 1), in: clean),
               let port = Int(clean[r]), (1...65535).contains(port) { return port }
        }
        return nil
    }
}
