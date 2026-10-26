import Testing
import Foundation
@testable import NexCore

@Suite struct DevicesParsingTests {
    static let simctl = """
    {"devices":{
      "com.apple.CoreSimulator.SimRuntime.iOS-26-0":[
        {"udid":"A1","isAvailable":true,"state":"Shutdown","name":"iPhone 17 Pro","deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"},
        {"udid":"A2","isAvailable":true,"state":"Booted","name":"iPad Air","deviceTypeIdentifier":"x"}],
      "com.apple.CoreSimulator.SimRuntime.watchOS-26-0":[
        {"udid":"W1","isAvailable":true,"state":"Shutdown","name":"Apple Watch","deviceTypeIdentifier":"w"}],
      "com.apple.CoreSimulator.SimRuntime.iOS-18-2":[
        {"udid":"B1","isAvailable":false,"state":"Shutdown","name":"Broken","deviceTypeIdentifier":"y"}]
    }}
    """

    @Test func parsesAvailableIOSSimulatorsWithRuntimeNames() {
        let sims = DeviceParsers.simulators(fromSimctlJSON: Self.simctl)
        #expect(sims.map(\.name) == ["iPad Air", "iPhone 17 Pro"])          // booted first, then by name
        #expect(sims.first { $0.udid == "A1" }?.runtime == "iOS 26.0")
        #expect(sims.first { $0.udid == "A2" }?.isBooted == true)
        #expect(!sims.contains { $0.udid == "W1" || $0.udid == "B1" })      // iOS only, available only
    }

    @Test func badSimctlOutputGivesNothing() {
        #expect(DeviceParsers.simulators(fromSimctlJSON: "oops").isEmpty)
    }

    @Test func parsesAndroidVirtualDevicesIgnoringLogNoise() {
        let out = "INFO    | Storing crashdata in: /tmp/x\nPixel_9\nMedium_Phone_API_35\n\n"
        #expect(DeviceParsers.avds(fromListOutput: out) == ["Pixel_9", "Medium_Phone_API_35"])
    }

    @Test func androidSDKIsFoundInTheUsualPlaces() {
        let t = TempTree()
        t.write("sdk/emulator/emulator", ""); t.write("sdk/platform-tools/adb", "")
        let sdk = t.root.appendingPathComponent("sdk")
        #expect(DeviceParsers.androidSDK(environment: ["ANDROID_HOME": sdk.path], home: URL(fileURLWithPath: "/nope")) == sdk)
        #expect(DeviceParsers.androidSDK(environment: [:], home: URL(fileURLWithPath: "/nope")) == nil)
    }

    @Test func friendlyAVDNames() {
        #expect(DeviceParsers.displayName(forAVD: "Pixel_9") == "Pixel 9")
        #expect(DeviceParsers.displayName(forAVD: "Medium_Phone_API_35") == "Medium Phone API 35")
    }
}

@Suite struct SimulatorShortlistTests {
    private func sim(_ name: String, _ runtime: String, booted: Bool = false) -> SimulatorDevice {
        SimulatorDevice(udid: name + runtime, name: name, runtime: runtime, isBooted: booted)
    }

    @Test func shortlistIsBootedPlusTheNewestRuntimeCapped() {
        let all = [sim("iPhone 16", "iOS 18.5", booted: true), sim("iPhone 16 Pro", "iOS 18.5"),
                   sim("iPhone 17", "iOS 26.0"), sim("iPhone 17 Pro", "iOS 26.0"), sim("iPhone Air", "iOS 26.0")]
        let short = DeviceParsers.shortlist(all, limit: 3)
        #expect(short.map(\.name) == ["iPhone 16", "iPhone 17", "iPhone 17 Pro"])
    }

    @Test func newestRuntimeComparesVersionsNumerically() {
        let all = [sim("A", "iOS 9.3"), sim("B", "iOS 18.5"), sim("C", "iOS 26.0")]
        #expect(DeviceParsers.shortlist(all, limit: 5).map(\.name) == ["C"])
    }
}
