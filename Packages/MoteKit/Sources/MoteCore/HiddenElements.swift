import Foundation

/// A page element someone hid for good, found again by its CSS selector.
public struct HiddenElement: Codable, Identifiable, Equatable, Sendable {
    public var selector: String
    /// What the list calls it.
    public var label: String
    /// Its size and place when hidden, since hidden it can't be measured;
    /// tells apart elements with the same label.
    public var note: String?
    public var date: Date

    public var id: String { selector }

    public init(selector: String, label: String, note: String? = nil, date: Date = Date()) {
        self.selector = selector
        self.label = label
        self.note = note
        self.date = date
    }
}

/// Every hidden element, by site (`Address.siteHost`), oldest first. Kept as
/// a plain `{site: [element]}` object in JSON.
public struct HiddenElements: Codable, Equatable, Sendable {
    public private(set) var bySite: [String: [HiddenElement]]

    public init(_ bySite: [String: [HiddenElement]] = [:]) { self.bySite = bySite }

    public init(from decoder: Decoder) throws {
        bySite = try decoder.singleValueContainer().decode([String: [HiddenElement]].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(bySite)
    }

    public func on(_ site: String?) -> [HiddenElement] {
        site.flatMap { bySite[$0] } ?? []
    }

    /// False when that selector was already hidden there.
    @discardableResult
    public mutating func hide(_ element: HiddenElement, on site: String) -> Bool {
        guard !on(site).contains(where: { $0.selector == element.selector }) else { return false }
        bySite[site, default: []].append(element)
        return true
    }

    public mutating func restore(_ selector: String, on site: String) {
        set(on(site).filter { $0.selector != selector }, on: site)
    }

    /// Brings back the last one hidden there.
    public mutating func undo(on site: String) -> HiddenElement? {
        var list = on(site)
        let last = list.popLast()
        set(list, on: site)
        return last
    }

    public mutating func restoreAll(on site: String) { bySite[site] = nil }

    /// A site with nothing hidden isn't kept.
    private mutating func set(_ list: [HiddenElement], on site: String) {
        bySite[site] = list.isEmpty ? nil : list
    }
}
