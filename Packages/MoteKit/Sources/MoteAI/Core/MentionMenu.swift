import Foundation

/// The @-mention picker: the other tabs a chat may be told about, and what of
/// the composer's text is the mention being typed.
///
/// Pure rules only, so they can be reasoned about and tested apart from the
/// SwiftUI that draws the picker: which tabs a query offers, whether a draft
/// holds a mention at its end, and the draft with that mention taken out.
public enum MentionMenu {
    /// One tab the picker offers: its name and its site, and a stable id the
    /// caller can find it by when it is chosen.
    public struct Candidate: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let host: String

        public init(id: String, title: String, host: String) {
            self.id = id
            self.title = title
            self.host = host
        }
    }

    /// The candidates whose title or site contains `query`, case- and
    /// diacritic-insensitively. A blank query offers them all, in order.
    public static func matching(_ query: String, in candidates: [Candidate]) -> [Candidate] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return candidates }
        return candidates.filter {
            $0.title.localizedCaseInsensitiveContains(needle) || $0.host.localizedCaseInsensitiveContains(needle)
        }
    }

    /// The text being typed after an @ at the end of `draft`, when there is
    /// one: the token must begin the draft or follow a space, run to the end
    /// without a space, and the draft must not end with a space (a finished
    /// mention is not being typed). Empty for a lone `@`. Nil when no mention
    /// is being typed.
    public static func query(in draft: String) -> String? {
        guard let last = draft.last, !last.isWhitespace else { return nil }
        let token = draft.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
        guard token.hasPrefix("@") else { return nil }
        return String(token.dropFirst())
    }

    /// `draft` with the mention being typed taken out, so choosing a tab
    /// leaves the message as it was before the @. The draft is returned
    /// unchanged when no mention is being typed.
    public static func cleared(_ draft: String) -> String {
        guard query(in: draft) != nil else { return draft }
        var kept = draft[...]
        while let last = kept.last, !last.isWhitespace { kept = kept.dropLast() }
        while let last = kept.last, last.isWhitespace { kept = kept.dropLast() }
        return String(kept)
    }
}
