import Testing
import Foundation
@testable import NexCore

@Suite struct SettingsTests {
    @Test func firstNameTakenFromFullName() {
        #expect(AppSettings.firstName(from: "David Niyonshuti") == "David")
        #expect(AppSettings.firstName(from: "  ") == "there")
        #expect(AppSettings.firstName(from: "") == "there")
    }

    @Test func defaultsPointAtNexventuresFolder() {
        let d = AppSettings.defaults()
        #expect(d.scanRoot.path.hasSuffix("Documents/Nexventures"))
        #expect(d.showDockIcon)
        #expect(d.pinnedProjectIDs.isEmpty)
        #expect(!d.displayName.isEmpty)
    }

    @Test func settingsRoundTripThroughDisk() {
        let t = TempTree()
        let file = t.root.appendingPathComponent("s.json")
        let store = SettingsStore(fileURL: file)
        store.settings.displayName = "Dave"
        store.settings.pinnedProjectIDs = ["x"]
        store.save()
        let reloaded = SettingsStore(fileURL: file)
        #expect(reloaded.settings.displayName == "Dave")
        #expect(reloaded.settings.pinnedProjectIDs == ["x"])
    }

    @Test func corruptSettingsFileFallsBackToDefaults() {
        let t = TempTree()
        let file = t.write("s.json", "{{{ nope")
        #expect(SettingsStore(fileURL: file).settings == AppSettings.defaults())
    }

    @Test func snapshotRoundTrip() {
        let t = TempTree()
        let snap = WidgetSnapshot(
            running: [.init(projectName: "CleanPay", kind: .frontend, port: 5173)],
            pinned: [.init(id: "/p", name: "P")])
        SharedContainer.write(snap, to: t.root)
        #expect(SharedContainer.read(from: t.root) == snap)
    }

    @Test func missingSnapshotReadsEmpty() {
        #expect(SharedContainer.read(from: TempTree().root) == WidgetSnapshot(running: [], pinned: []))
    }
}

@Suite struct SharedLocationTests {
    @Test func sharedDirectoryIsInRealHomeNotASandboxContainer() {
        let path = SharedContainer.defaultDirectory.path
        #expect(path.hasSuffix("Library/Application Support/NexLauncher"))
        #expect(!path.contains("/Containers/"))
    }

    @Test func realHomeMatchesPasswdEntry() {
        #expect(AppSettings.realHome.path == String(cString: getpwuid(getuid()).pointee.pw_dir))
    }
}
