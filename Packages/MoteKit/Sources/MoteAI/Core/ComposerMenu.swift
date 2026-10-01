import Foundation

/// Which picker the composer offers over a draft: the `/` skills, the
/// `@` mentions, or neither. The two do not argue — a draft opening with a
/// slash is a skill, and a slash anywhere else is literal; a mention being
/// typed ends the draft and follows a space, so it can begin once a command
/// is finished.
///
/// Pure, so the decision can be tested apart from the SwiftUI that draws it.
public enum ComposerMenu: Equatable, Sendable {
    /// The `/` skills are being typed.
    case skills
    /// A `@` mention is being typed.
    case mentions
    /// Neither: ordinary prose.
    case none

    /// Which menu `draft` calls for.
    public static func of(_ draft: String) -> ComposerMenu {
        if Skill.query(in: draft) != nil { return .skills }
        if MentionMenu.query(in: draft) != nil { return .mentions }
        return .none
    }
}
