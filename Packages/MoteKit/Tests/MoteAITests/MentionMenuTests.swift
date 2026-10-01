import Foundation
import Testing

@testable import MoteAI

/// The @-mention picker's pure rules: which tabs a typed query offers, and
/// what of the composer's text the mention being typed is.
@Suite("Mention menu")
struct MentionMenuTests {
    private let tabs = [
        MentionMenu.Candidate(id: "a", title: "Swift.org", host: "swift.org"),
        MentionMenu.Candidate(id: "b", title: "The Verge", host: "theverge.com"),
        MentionMenu.Candidate(id: "c", title: "Hacker News", host: "news.ycombinator.com"),
    ]

    @Test("A blank query offers every tab, in order")
    func blank() {
        #expect(MentionMenu.matching("", in: tabs) == tabs)
        #expect(MentionMenu.matching("   ", in: tabs) == tabs)
    }

    @Test("A query keeps the tabs whose name or site contains it, ignoring case")
    func matching() {
        #expect(MentionMenu.matching("swift", in: tabs).map(\.id) == ["a"])
        #expect(MentionMenu.matching("VERGE", in: tabs).map(\.id) == ["b"])
        #expect(MentionMenu.matching("ycombinator", in: tabs).map(\.id) == ["c"])
        #expect(MentionMenu.matching("zzz", in: tabs).isEmpty)
    }

    @Test("A mention being typed is the @-token at the end of the draft")
    func query() {
        #expect(MentionMenu.query(in: "hi @sw") == "sw")
        #expect(MentionMenu.query(in: "@") == "")
        #expect(MentionMenu.query(in: "line\n@verge") == "verge")
        #expect(MentionMenu.query(in: "hi") == nil)
        // An @ inside a word is not a mention.
        #expect(MentionMenu.query(in: "mail a@b") == nil)
        // A finished mention (space after it) is not being typed.
        #expect(MentionMenu.query(in: "hi @sw ") == nil)
    }

    @Test("Choosing a tab takes the mention being typed out of the draft")
    func cleared() {
        #expect(MentionMenu.cleared("hello @sw") == "hello")
        #expect(MentionMenu.cleared("@sw") == "")
        #expect(MentionMenu.cleared("one\ntwo @sw") == "one\ntwo")
        // Nothing being typed: left as it is.
        #expect(MentionMenu.cleared("hello") == "hello")
    }
}
