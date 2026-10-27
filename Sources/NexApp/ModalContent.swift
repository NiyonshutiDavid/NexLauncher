import Foundation

/// A pop-up shown over the whole window. Each interface puts its own view in `payload`.
public struct ModalContent: Identifiable {
    public let id = UUID()
    public let payload: Any
    public init(payload: Any) { self.payload = payload }
}
