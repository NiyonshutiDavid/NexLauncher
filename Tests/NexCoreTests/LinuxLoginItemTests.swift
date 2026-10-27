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

    /// Inside a Flatpak, XDG_CONFIG_HOME is the app's private folder, which the session never reads: the entry
    /// must go to the real ~/.config/autostart.
    @Test func flatpakWritesToTheRealAutostartFolder() {
        let sandboxed = ["XDG_CONFIG_HOME": "/home/alex/.var/app/net.nexventures.NexLauncher/config"]
        let item = XDGAutostart.forCurrentUser(environment: sandboxed, flatpak: true, home: URL(fileURLWithPath: "/home/alex"))
        #expect(item.directory.path == "/home/alex/.config/autostart")
        #expect(item.exec == "flatpak run net.nexventures.NexLauncher")
        let native = XDGAutostart.forCurrentUser(environment: ["XDG_CONFIG_HOME": "/x/cfg"], flatpak: false, home: URL(fileURLWithPath: "/home/alex"))
        #expect(native.directory.path == "/x/cfg/autostart")
    }
}
