import Foundation

/// A message that rises from the bottom of the window for a moment: a line,
/// perhaps a second one, a symbol, and something to do about it.
struct Announcement: Equatable {
    var text: String
    var detail: String?
    var symbol: String?
    var action: Action?
    /// Two messages with the same words are still two messages.
    private let id = UUID()

    init(_ text: String, detail: String? = nil, symbol: String? = nil, action: Action? = nil) {
        self.text = text
        self.detail = detail
        self.symbol = symbol
        self.action = action
    }

    struct Action {
        let title: String
        let perform: @MainActor () -> Void
    }

    /// Seconds on screen: a plain line goes quickly; one to read or act on stays.
    var lasts: Double { action != nil ? 8 : detail != nil ? 4 : 2 }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
}
