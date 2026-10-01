import Foundation
import Testing

@testable import MoteAI

/// Which picker the composer offers over a draft: the `/` skills, the
/// `@` mentions, or neither. The two never argue: a draft starting with a
/// slash is a skill, and a mid-text slash is literal.
@Suite("Composer menu")
struct ComposerMenuTests {
    @Test("A draft opening with a slash token offers the skills")
    func skills() {
        #expect(ComposerMenu.of("/") == .skills)
        #expect(ComposerMenu.of("/su") == .skills)
    }

    @Test("A draft ending in a mention offers the tabs")
    func mentions() {
        #expect(ComposerMenu.of("@") == .mentions)
        #expect(ComposerMenu.of("@sw") == .mentions)
        #expect(ComposerMenu.of("hi @sw") == .mentions)
    }

    @Test("A skill command finished, the next token is mentionable again")
    func handoff() {
        #expect(ComposerMenu.of("/su @sw") == .mentions)
    }

    @Test("Ordinary prose, or a literal slash, offers neither")
    func none() {
        #expect(ComposerMenu.of("") == .none)
        #expect(ComposerMenu.of("hello") == .none)
        #expect(ComposerMenu.of("ask /summary") == .none)
        #expect(ComposerMenu.of("/su ") == .none)
        #expect(ComposerMenu.of("email a@b") == .none)
    }
}
