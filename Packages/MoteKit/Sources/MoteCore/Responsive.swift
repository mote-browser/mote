import Foundation

public enum ResponsiveError: String, LocalizedError {
    case name = "Use a name between 1 and 80 characters."
    case dimensions = "Viewport dimensions must be between 240 and 3840 CSS pixels."
    case userAgent = "Use a user agent shorter than 513 characters, without line breaks."
    case views = "A workspace needs 1 to 6 different views."

    public var errorDescription: String? { rawValue }
}

/// CSS pixels, independent of the canvas's display scale and the Mac's pixel density.
public struct ResponsiveViewport: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let width: Int
    public let height: Int
    public let userAgent: String?

    public init(id: UUID = UUID(), name: String, width: Int, height: Int, userAgent: String? = nil) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...80).contains(name.count) else { throw ResponsiveError.name }
        guard (240...3840).contains(width), (240...3840).contains(height) else { throw ResponsiveError.dimensions }
        let agent = userAgent?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (userAgent?.count ?? 0) <= 512, userAgent?.contains(where: { $0.isNewline || $0 == "\0" }) != true else {
            throw ResponsiveError.userAgent
        }
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.userAgent = agent?.isEmpty == false ? agent : nil
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(UUID.self, forKey: .id), name: values.decode(String.self, forKey: .name),
            width: values.decode(Int.self, forKey: .width), height: values.decode(Int.self, forKey: .height),
            userAgent: values.decodeIfPresent(String.self, forKey: .userAgent))
    }

    public var rotated: Self {
        // Already validated; rotation preserves both dimension bounds.
        try! Self(id: id, name: name, width: height, height: width, userAgent: userAgent)
    }

    public static let presets: [Self] = [
        try! Self(name: "Phone", width: 390, height: 844),
        try! Self(name: "Tablet", width: 768, height: 1024),
        try! Self(name: "Desktop", width: 1440, height: 900),
    ]
}

/// Saved view settings only: URLs, page contents and private sessions are never stored here.
public struct ResponsiveLayout: Codable, Equatable, Identifiable, Sendable {
    public static let maximumViews = 6
    public let id: UUID
    public let name: String
    public let viewports: [ResponsiveViewport]

    public init(id: UUID = UUID(), name: String, viewports: [ResponsiveViewport]) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...80).contains(name.count) else { throw ResponsiveError.name }
        guard (1...Self.maximumViews).contains(viewports.count), Set(viewports.map(\.id)).count == viewports.count else {
            throw ResponsiveError.views
        }
        self.id = id
        self.name = name
        self.viewports = viewports
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(UUID.self, forKey: .id), name: values.decode(String.self, forKey: .name),
            viewports: values.decode([ResponsiveViewport].self, forKey: .viewports))
    }
}
