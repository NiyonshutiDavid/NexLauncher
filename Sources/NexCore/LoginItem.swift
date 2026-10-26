import Foundation
import Observation
import ServiceManagement

public protocol LoginItemControlling: Sendable {
    var isEnabled: Bool { get }
    func setEnabled(_ on: Bool) throws
}

/// Registers the main app as a login item.
public struct SMLoginItem: LoginItemControlling {
    public init() {}
    public var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    public func setEnabled(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

/// Observable wrapper: keeps the toggle truthful and surfaces failures instead of swallowing them.
@MainActor @Observable
public final class LaunchAtLogin {
    public private(set) var isEnabled: Bool
    public private(set) var errorMessage: String?
    private let controller: LoginItemControlling

    public init(controller: LoginItemControlling = SMLoginItem()) {
        self.controller = controller
        self.isEnabled = controller.isEnabled
    }

    public func set(_ on: Bool) {
        do {
            try controller.setEnabled(on)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isEnabled = controller.isEnabled
    }

    public func refresh() { isEnabled = controller.isEnabled }
}
