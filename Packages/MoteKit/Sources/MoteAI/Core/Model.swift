import Foundation

/// A model a provider offers.
public struct Model: Identifiable, Hashable, Codable, Sendable {
    /// What the provider calls it, as sent in requests.
    public var id: String
    /// What people call it.
    public var name: String
    /// A few words on what it's good for.
    public var detail: String?

    public init(id: String, name: String? = nil, detail: String? = nil) {
        self.id = id
        self.name = name ?? id
        self.detail = detail
    }
}
