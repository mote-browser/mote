import Testing

@testable import MoteAI

@Suite("Markdown")
struct MarkdownTests {
    @Test("Paragraphs are split by blank lines and keep their line breaks")
    func paragraphs() {
        let blocks = Markdown.parse("One\nstill one\n\nTwo")
        #expect(blocks == [.paragraph("One\nstill one"), .paragraph("Two")])
    }

    @Test("Headings take their level from the hashes")
    func headings() {
        let blocks = Markdown.parse("# Big\n### Small ###\n#Not a heading")
        #expect(blocks == [.heading(level: 1, text: "Big"), .heading(level: 3, text: "Small"), .paragraph("#Not a heading")])
    }

    @Test("A fenced code block keeps its language and its text exactly")
    func code() {
        let blocks = Markdown.parse("Look:\n```swift\nlet a = 1\n\n  print(a)\n```\nAfter")
        #expect(
            blocks == [
                .paragraph("Look:"), .code(language: "swift", text: "let a = 1\n\n  print(a)", closed: true), .paragraph("After"),
            ])
    }

    @Test("A code block still arriving is shown open, with what has come so far")
    func openCode() {
        let blocks = Markdown.parse("```py\nprint(1)\npri")
        #expect(blocks == [.code(language: "py", text: "print(1)\npri", closed: false)])
    }

    @Test("A fence only closes on the same character, at least as long")
    func fenceMatching() {
        let blocks = Markdown.parse("````\n```\ninside\n~~~\n````")
        #expect(blocks == [.code(language: nil, text: "```\ninside\n~~~", closed: true)])
    }

    @Test("Lines of dashes, stars or underscores are rules")
    func rules() {
        #expect(Markdown.parse("a\n\n---\n\n* * *\n___") == [.paragraph("a"), .rule, .rule, .rule])
    }

    @Test("Bullets make an unordered list, one item per bullet")
    func bulletList() {
        let blocks = Markdown.parse("- one\n- two\n* three")
        #expect(
            blocks == [
                .list(Markdown.List(ordered: false, start: 1, items: [item("one"), item("two")])),
                .list(Markdown.List(ordered: false, start: 1, items: [item("three")])),
            ])
    }

    @Test("Numbers make an ordered list that keeps its first number")
    func orderedList() {
        let blocks = Markdown.parse("3. three\n4. four")
        #expect(blocks == [.list(Markdown.List(ordered: true, start: 3, items: [item("three"), item("four")]))])
    }

    @Test("Indented lines under an item belong to it, nested lists included")
    func nestedList() {
        let blocks = Markdown.parse("- parent\n  more text\n  - child\n- next")
        let child = Markdown.Block.list(Markdown.List(ordered: false, start: 1, items: [item("child")]))
        let parent = Markdown.Item(blocks: [.paragraph("parent\nmore text"), child])
        #expect(blocks == [.list(Markdown.List(ordered: false, start: 1, items: [parent, item("next")]))])
    }

    @Test("A blank line between items keeps one list")
    func looseList() {
        let blocks = Markdown.parse("1. a\n\n2. b\n\nAfter")
        #expect(blocks == [.list(Markdown.List(ordered: true, start: 1, items: [item("a"), item("b")])), .paragraph("After")])
    }

    @Test("Task items know whether they are ticked")
    func tasks() {
        let blocks = Markdown.parse("- [ ] todo\n- [x] done")
        let items = [
            Markdown.Item(blocks: [.paragraph("todo")], checked: false), Markdown.Item(blocks: [.paragraph("done")], checked: true),
        ]
        #expect(blocks == [.list(Markdown.List(ordered: false, start: 1, items: items))])
    }

    @Test("A list interrupts a paragraph, as chat replies expect")
    func listAfterParagraph() {
        let blocks = Markdown.parse("Steps:\n1. first\n2. second")
        #expect(blocks == [.paragraph("Steps:"), .list(Markdown.List(ordered: true, start: 1, items: [item("first"), item("second")]))])
    }

    @Test("Quotes hold blocks of their own")
    func quotes() {
        let blocks = Markdown.parse("> # Title\n> said\nthis\n\nout")
        #expect(blocks == [.quote([.heading(level: 1, text: "Title"), .paragraph("said\nthis")]), .paragraph("out")])
    }

    @Test("A table needs its delimiter row, reads alignment from it and ends at a line without pipes")
    func table() {
        let blocks = Markdown.parse("| Name | Size |\n|:--|--:|\n| a | 1 |\n| b \\| c | 2 |\nafter")
        let table = Markdown.Table(
            header: ["Name", "Size"], alignments: [.leading, .trailing], rows: [["a", "1"], ["b | c", "2"]])
        #expect(blocks == [.table(table), .paragraph("after")])
    }

    @Test("Rows short of cells are filled, long ones cut to the header")
    func raggedTable() {
        let blocks = Markdown.parse("a | b\n--- | :-:\n1 |\n1 | 2 | 3")
        let table = Markdown.Table(header: ["a", "b"], alignments: [.none, .center], rows: [["1", ""], ["1", "2"]])
        #expect(blocks == [.table(table)])
    }

    @Test("Pipes without a delimiter row are just text")
    func notATable() {
        #expect(Markdown.parse("a | b\nc | d") == [.paragraph("a | b\nc | d")])
    }

    @Test("Windows line endings read the same")
    func carriageReturns() {
        #expect(Markdown.parse("# A\r\n\r\ntext") == [.heading(level: 1, text: "A"), .paragraph("text")])
    }

    @Test("Nothing but space is no blocks at all")
    func empty() {
        #expect(Markdown.parse("  \n\n ").isEmpty)
    }

    private func item(_ text: String) -> Markdown.Item { Markdown.Item(blocks: [.paragraph(text)]) }
}
