import Foundation

/// The draft the composer opens with when the person asks about a selection
/// from the page's own menu: the selection quoted as Markdown, then a light
/// instruction they can send or edit. Formatting is kept apart from the views
/// so it can be tested on its own.
public enum SelectionAsk {
    /// How much of a selection is quoted before it is cut short. A page can
    /// select a whole chapter; the quote is a way in, not the message.
    public static let limit = 1200

    /// What follows the quote. A placeholder to be replaced or sent as is.
    public static let instruction = "Ask about this selection…"

    /// The draft for `selection`, or nil when nothing was selected. The
    /// selection is trimmed, cut to `limit` characters with an ellipsis when
    /// longer, and quoted line by line as a Markdown blockquote.
    public static func draft(for selection: String, limit: Int = SelectionAsk.limit) -> String? {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let quoted = cut(trimmed, to: limit).replacingOccurrences(of: "\n", with: "\n> ")
        return "> \"" + quoted + "\"\n\n" + instruction
    }

    /// The text at most `limit` characters, with an ellipsis when it was cut.
    private static func cut(_ text: String, to limit: Int) -> String {
        guard limit > 0, text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }
}
