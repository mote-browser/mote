import Foundation

/// The `/` skills the composer offers: a small, fixed set of built-in prompts,
/// each a shorter way to word a common ask. Typing `/` at the very start of a
/// draft opens the picker; choosing a skill replaces the draft with its prompt,
/// with whatever was typed after the command appended as a parameter.
///
/// Pure rules only, so they can be reasoned about and tested apart from the
/// SwiftUI that draws the picker: which command a draft is typing, which
/// skills a query offers, when one is named unambiguously, and the draft a
/// chosen skill becomes.
public enum Skill {
    /// One built-in skill: the command typed after `/`, a short name for the
    /// picker, and the prompt the draft becomes.
    public struct Item: Equatable, Sendable, Identifiable {
        public let command: String
        public let title: String
        public let prompt: String

        public init(command: String, title: String, prompt: String) {
            self.command = command
            self.title = title
            self.prompt = prompt
        }

        /// The id is the command, which is unique.
        public var id: String { command }

        /// How the command is typed, with its slash: `/summary`.
        public var typed: String { "/" + command }
    }

    /// Summarize the page in hand.
    public static let summary = Item(command: "summary", title: "Summarize", prompt: "Summarize this page")

    /// Explain the page simply.
    public static let eli5 = Item(command: "eli5", title: "Explain simply", prompt: "Explain this page in simple terms")

    /// Pull the page's key points.
    public static let keypoints = Item(command: "keypoints", title: "Key points", prompt: "Extract the key points of this page")

    /// Pull the page's next steps.
    public static let actions = Item(command: "actions", title: "Next steps", prompt: "Extract actionable next steps from this page")

    /// The built-ins, in the order the picker shows them.
    public static let all: [Item] = [summary, eli5, keypoints, actions]

    /// The skills whose command starts with `query`, case-insensitively. A
    /// blank query offers them all, in order.
    public static func matching(_ query: String, in skills: [Item] = Skill.all) -> [Item] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return skills }
        return skills.filter { $0.command.lowercased().hasPrefix(needle.lowercased()) }
    }

    /// The skill `query` names, when it names exactly one. Nil when it names
    /// none or several: an ambiguous command is offered as a list, never
    /// expanded to a guess.
    public static func resolve(_ query: String, in skills: [Item] = Skill.all) -> Item? {
        let matches = matching(query, in: skills)
        return matches.count == 1 ? matches[0] : nil
    }

    /// The command being typed at the very start of `draft`: the token after a
    /// leading slash, while the draft holds nothing but that token. Empty for
    /// a lone `/`. Nil when no skill is being typed — a slash anywhere but the
    /// first character is literal, and once a space is typed the command is
    /// finished.
    public static func query(in draft: String) -> String? {
        guard draft.hasPrefix("/") else { return nil }
        guard !draft.contains(where: \.isWhitespace) else { return nil }
        return String(draft.dropFirst())
    }

    /// The draft `draft` becomes when its leading command is chosen: the
    /// skill's prompt, then whatever was typed after the command, as a
    /// parameter. Nil when the draft does not open with a known, unambiguous
    /// command, so a literal slash is left exactly as it was typed.
    public static func expand(_ draft: String) -> String? {
        guard draft.hasPrefix("/") else { return nil }
        let token = draft.prefix { !$0.isWhitespace }
        guard let skill = resolve(String(token.dropFirst())) else { return nil }
        let rest = draft.dropFirst(token.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? skill.prompt : skill.prompt + " " + rest
    }
}
