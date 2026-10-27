import Foundation

extension Pipe {
    /// A pipe that other child processes won't inherit.
    public static func closeOnExec() -> Pipe {
        Pipe()
    }
}
