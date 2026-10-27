import Testing
import Foundation
@testable import NexCore

@Suite struct LinuxLoginItemTests {
    @Test func writesAutostartFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("autostart-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let item = XDGAutostart(directory: dir, exec: "flatpak run net.nexventures.NexLauncher")
        #expect(!item.isEnabled)
        try item.setEnabled(true)
        let file = dir.appendingPathComponent("net.nexventures.NexLauncher.desktop")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("Exec=flatpak run net.nexventures.NexLauncher"))
        #expect(text.contains("X-GNOME-Autostart-enabled=true"))
        #expect(item.isEnabled)
        try item.setEnabled(false)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(!item.isEnabled)
    }
}
