import Foundation

/// What a chat is told about the page the person is looking at, when they
/// choose to share it.
///
/// A page is shared when it is taken: its address and title always go to the
/// model, its text when it was read, and what the person has selected as a
/// quotation. A chat outlives navigation — the page it was opened over is
/// detached, and the chat goes on without it, until another page is attached.
public struct PageContext: Equatable, Sendable {
    public var url: URL
    public var title: String
    /// The page's text, when it was read (Reader).
    public var text: String?
    /// What the person has selected on the page, when anything is.
    public var selection: String?
    /// Whether the page is still shared with the model. Detached, the page is
    /// kept but the model no longer sees it.
    public private(set) var isAttached: Bool

    public init(url: URL, title: String, text: String? = nil, selection: String? = nil, isAttached: Bool = true) {
        self.url = url
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.text = Self.clean(text)
        self.selection = Self.clean(selection)
        self.isAttached = isAttached
    }

    /// Whether the model sees the page now.
    public var isActive: Bool { isAttached }

    /// Shares the page with the model again.
    public mutating func attach() { isAttached = true }

    /// Stops sharing the page, without losing it.
    public mutating func detach() { isAttached = false }

    /// Blank text is no text.
    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
