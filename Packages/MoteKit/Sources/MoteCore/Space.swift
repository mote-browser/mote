import Foundation

/// A set of tabs of its own in the window, with its own website data or the
/// first space's. Kept in spaces.json; the field names are that file's format.
public struct Space: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    /// No longer used; kept so older files still read.
    public var colour: Int
    /// One of `Space.icons`' symbols.
    public var icon: String?
    /// Signed in wherever the first space is, sharing its website data. nil,
    /// in older spaces, means data of its own.
    public var sharesSignIns: Bool?
    /// Where its downloads go; nil for the folder in Settings.
    public var downloads: String?

    public init(id: UUID, name: String, icon: String? = nil, sharesSignIns: Bool? = nil, downloads: String? = nil) {
        self.id = id
        self.name = name
        colour = 0
        self.icon = icon
        self.sharesSignIns = sharesSignIns
        self.downloads = downloads
    }

    /// The first space: the default session and data store, so turning spaces
    /// on signs nobody out.
    public static let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    public var isFirst: Bool { id == Self.firstID }
    public var ownData: Bool { !isFirst && sharesSignIns != true }

    /// Its icon, or a house for the first space and a briefcase for others.
    public var symbol: String {
        icon.flatMap { icon in Self.icons.contains { $0.symbol == icon } ? icon : nil } ?? (isFirst ? "house" : "briefcase")
    }

    /// The icons a space can have: SF Symbols and their names.
    public static let icons: [(symbol: String, name: String)] = [
        ("briefcase", "Work"), ("building.2", "Office"), ("desktopcomputer", "Desktop"), ("laptopcomputer", "Laptop"),
        ("chevron.left.forwardslash.chevron.right", "Code"), ("terminal", "Terminal"), ("sparkles", "AI"),
        ("brain.head.profile", "Thinking"), ("lightbulb", "Ideas"), ("gamecontroller", "Games"), ("beach.umbrella", "Leisure"),
        ("cup.and.saucer", "Café"), ("music.note", "Music"), ("film", "Film"), ("paintpalette", "Art"), ("camera", "Photos"),
        ("house", "Home"), ("book", "Reading"), ("graduationcap", "Studies"), ("cart", "Shopping"), ("airplane", "Travel"),
        ("dumbbell", "Sport"), ("leaf", "Nature"), ("heart", "Personal"),
    ]
}

/// The window's spaces, the first one always first.
public struct SpaceList: Equatable, Sendable {
    public private(set) var spaces: [Space]

    /// From what was saved; the first space is made if it's missing.
    public init(saved: [Space]) {
        let first = saved.first(where: \.isFirst) ?? Space(id: Space.firstID, name: "Personal")
        spaces = [first] + saved.filter { !$0.isFirst }
    }

    public func index(of id: UUID) -> Int? { spaces.firstIndex { $0.id == id } }
    public func space(_ id: UUID) -> Space? { spaces.first { $0.id == id } }

    /// The first icon no space has yet.
    public var freeIcon: String {
        let used = Set(spaces.map(\.symbol))
        return Space.icons.first { !used.contains($0.symbol) }?.symbol ?? "briefcase"
    }

    public mutating func add(_ space: Space) { spaces.append(space) }

    /// Moves a space to `index`; ⌃1–⌃9 and swiping follow the order.
    @discardableResult
    public mutating func move(_ id: UUID, to index: Int) -> Bool {
        guard let from = self.index(of: id), spaces.indices.contains(index), from != index else { return false }
        spaces.insert(spaces.remove(at: from), at: index)
        return true
    }

    public mutating func edit(_ id: UUID, _ change: (inout Space) -> Void) {
        if let at = index(of: id) { change(&spaces[at]) }
    }

    /// Removes a space; never the first.
    @discardableResult
    public mutating func remove(_ id: UUID) -> Space? {
        guard id != Space.firstID, let at = index(of: id) else { return nil }
        return spaces.remove(at: at)
    }

    /// The spaces sharing the first space's data.
    public var sharing: Set<UUID> { Set(spaces.filter { $0.sharesSignIns == true }.map(\.id)) }
}
