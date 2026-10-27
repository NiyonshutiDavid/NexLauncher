/// Turns launch at login on and off. Kept apart from LoginItem.swift, which the widget extension can't compile.
public protocol LoginItemControlling: Sendable {
    var isEnabled: Bool { get }
    func setEnabled(_ on: Bool) throws
}
