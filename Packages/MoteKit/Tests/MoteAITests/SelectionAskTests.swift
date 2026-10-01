import Foundation
import Testing

@testable import MoteAI

@Suite("Selection ask")
struct SelectionAskTests {
    @Test("Nothing selected has no draft to open the composer with")
    func empty() {
        #expect(SelectionAsk.draft(for: "") == nil)
        #expect(SelectionAsk.draft(for: "   \n\t ") == nil)
    }

    @Test("A selection becomes a quoted line with a light instruction after it")
    func singleLine() {
        #expect(
            SelectionAsk.draft(for: "the quick brown fox") == """
                > "the quick brown fox"

                \(SelectionAsk.instruction)
                """)
    }

    @Test("The selection is trimmed before it is quoted")
    func trimmed() {
        #expect(
            SelectionAsk.draft(for: "  spaced  ") == """
                > "spaced"

                \(SelectionAsk.instruction)
                """)
    }

    @Test("Every line of a multi-line selection stays inside the quote")
    func multiLine() {
        #expect(
            SelectionAsk.draft(for: "first\nsecond\nthird") == """
                > "first
                > second
                > third"

                \(SelectionAsk.instruction)
                """)
    }

    @Test("An absurdly long selection is cut short, with an ellipsis, before it is quoted")
    func capped() {
        let long = String(repeating: "a", count: 40)
        let draft = SelectionAsk.draft(for: long, limit: 12)!
        #expect(draft.contains("> \"" + String(repeating: "a", count: 12) + "…\""))
        #expect(!draft.contains(String(repeating: "a", count: 13)))
        // The cap applies to the selection, not to the whole draft.
        #expect(draft.hasSuffix(SelectionAsk.instruction))
    }

    @Test("A selection at the cap is quoted whole")
    func atCap() {
        let exact = String(repeating: "b", count: 12)
        #expect(SelectionAsk.draft(for: exact, limit: 12)!.contains("> \"\(exact)\""))
    }
}
