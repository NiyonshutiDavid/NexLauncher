import Testing
import Foundation
@testable import NexCore

@Suite struct SettingsV2Tests {
    @Test func v1SettingsFileLoadsWithV2Defaults() throws {
        let json = #"{"displayName":"Dave","scanRoot":"file:///tmp/x/","showDockIcon":false,"pinnedProjectIDs":["a"]}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(s.displayName == "Dave" && !s.showDockIcon && s.pinnedProjectIDs == ["a"])
        #expect(s.theme == .ember)
        #expect(s.appearance == .system)
        #expect(s.viewMode == .cards)
        #expect(s.defaultBranch == "main")
        #expect(s.defaultPullStrategy == .ffOnly)
        #expect(s.dismissedCTAs.isEmpty)
        #expect(s.lastRun == nil && s.avatarPhotoPath == nil && s.avatarColorHex == nil)
        #expect(!s.widgetsConfirmed)
    }

    @Test func v2FieldsRoundTrip() throws {
        var s = AppSettings.defaults()
        s.theme = .ocean; s.appearance = .dark; s.viewMode = .folders
        s.dismissedCTAs = ["themes", "login"]
        s.lastRun = LastRun(projectID: "/p", action: "Both")
        s.defaultBranch = "trunk"; s.defaultPullStrategy = .rebase
        s.avatarColorHex = "#cf3f0e"; s.avatarPhotoPath = "/tmp/me.png"; s.widgetsConfirmed = true
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }

    @Test func unknownKeysAreIgnored() throws {
        let json = #"{"displayName":"D","scanRoot":"file:///tmp/","showDockIcon":true,"pinnedProjectIDs":[],"futureThing":42}"#
        #expect(throws: Never.self) { _ = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8)) }
    }

    @Test func initialsFromName() {
        #expect(AppSettings.initials(from: "David Niyonshuti") == "DN")
        #expect(AppSettings.initials(from: "david") == "D")
        #expect(AppSettings.initials(from: "") == "?")
        #expect(AppSettings.initials(from: "  a  b  c ") == "AB")
    }
}
