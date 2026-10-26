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
