import Foundation
import Testing

@testable import MoteAI

/// The `/` skills' pure rules: what the built-ins are, which a typed command
/// offers, when one is named unambiguously, and the draft a chosen skill
/// becomes.
@Suite("Skills")
struct SkillTests {
    @Test("The built-in skills are the four fixed commands, in order")
    func builtins() {
        #expect(Skill.all.map(\.command) == ["summary", "eli5", "keypoints", "actions"])
        #expect(Skill.summary.prompt == "Summarize this page")
        #expect(Skill.eli5.prompt == "Explain this page in simple terms")
        #expect(Skill.keypoints.prompt == "Extract the key points of this page")
        #expect(Skill.actions.prompt == "Extract actionable next steps from this page")
    }

    @Test("A lone slash offers every skill, in order")
    func blank() {
        #expect(Skill.matching("") == Skill.all)
    }

    @Test("A query keeps the skills whose command starts with it, ignoring case")
    func matching() {
        #expect(Skill.matching("su").map(\.command) == ["summary"])
        #expect(Skill.matching("KEY").map(\.command) == ["keypoints"])
        #expect(Skill.matching("e").map(\.command) == ["eli5"])
        #expect(Skill.matching("zzz").isEmpty)
    }

    @Test("A query most skills share offers them all, none of them named")
    func ambiguous() {
        let shared = [
            Skill.Item(command: "sum", title: "Sum", prompt: "Add them up"),
            Skill.Item(command: "summary", title: "Summary", prompt: "Summarize"),
        ]
        #expect(Skill.matching("s", in: shared).map(\.command) == ["sum", "summary"])
        #expect(Skill.resolve("s", in: shared) == nil)
        // An empty query names nothing: several are left, and a lone slash
        // must not expand to the first skill.
        #expect(Skill.resolve("", in: shared) == nil)
        #expect(Skill.resolve("") == nil)
    }

    @Test("A query naming exactly one skill resolves to it")
    func resolve() {
        #expect(Skill.resolve("su") == Skill.summary)
        #expect(Skill.resolve("SUMMARY") == Skill.summary)
        #expect(Skill.resolve("zzz") == nil)
    }

    @Test("A skill is being typed only when the draft is a lone leading slash token")
    func query() {
        #expect(Skill.query(in: "/") == "")
        #expect(Skill.query(in: "/su") == "su")
        #expect(Skill.query(in: "/SU") == "SU")
        // A slash anywhere but the very start is literal text.
        #expect(Skill.query(in: "ask /su") == nil)
        #expect(Skill.query(in: "line\n/su") == nil)
        // Once a space is typed the command is finished, not being typed.
        #expect(Skill.query(in: "/su ") == nil)
        #expect(Skill.query(in: "/su @tab") == nil)
    }

    @Test("Choosing a skill gives its prompt")
    func expansion() {
        #expect(Skill.expand("/summary") == "Summarize this page")
        #expect(Skill.expand("/eli5") == "Explain this page in simple terms")
        #expect(Skill.expand("/actions") == "Extract actionable next steps from this page")
    }

    @Test("Text after the command parameterizes the prompt, and is trimmed")
    func parameterized() {
        #expect(Skill.expand("/summary in one line") == "Summarize this page in one line")
        #expect(Skill.expand("/summary   briefly  ") == "Summarize this page briefly")
        // A complete command names the skill even while it is only a prefix.
        #expect(Skill.expand("/sum here") == "Summarize this page here")
    }

    @Test("An unknown or literal slash does not expand, leaving the draft as typed")
    func noExpansion() {
        #expect(Skill.expand("/xyz") == nil)
        #expect(Skill.expand("/") == nil)
        #expect(Skill.expand("ask /summary") == nil)
        #expect(Skill.expand("") == nil)
    }
}
