import Testing

@testable import MoteAI

@Suite("Markdown as it streams")
struct MarkdownStreamTests {
    /// A reply with a bit of everything, and the places streaming cuts it
    /// awkwardly: mid-fence, mid-table, mid-list, a paragraph turning into a table.
    static let reply = """
        # Swift on servers

        Swift runs **well** on Linux, with [Vapor](https://vapor.codes) and Hummingbird.
        It compiles ahead of time.

        - Fast start
        - Low memory
          - even under load

        - A second item after a blank line

        1. Install
        2. Run

        > Quoted advice
        > on two lines

        | Framework | Stars |
        |:--|--:|
        | Vapor | 24k |
        | Hummingbird | 1k |

        ```swift
        let app = Application()
        try app.run()
        ```

        ---

        Name | Kind
        --- | ---
        a | b

        Last words, `code`, and a [link](https://example.com).
        """

    @Test("Fed a piece at a time, at every cut, it reads exactly as the whole")
    func everyCut() {
        let characters = Array(Self.reply)
        for step in [1, 3, 7, 16] {
            var stream = Markdown.Stream()
            var end = 0
            while end < characters.count {
                end = min(end + step, characters.count)
                let text = String(characters[..<end])
                stream.update(text)
                #expect(stream.blocks == Markdown.parse(text), "at \(end) of \(characters.count), \(step) at a time")
            }
        }
    }

    @Test("Blocks already finished are kept, not parsed again")
    func keepsFinished() {
        var stream = Markdown.Stream()
        stream.update("First paragraph.\n\nSecond paragraph.\n\nThird")
        #expect(stream.parsedFrom == 0)
        stream.update("First paragraph.\n\nSecond paragraph.\n\nThird paragraph, longer")
        // Only from the block before the last: the first is never read again.
        #expect(stream.parsedFrom == 2)
    }

    @Test("Text that changes rather than grows is read again from the start")
    func changed() {
        var stream = Markdown.Stream()
        stream.update("One\n\nTwo\n\nSources:\n- a")
        stream.update("One\n\nTwo")
        #expect(stream.blocks == Markdown.parse("One\n\nTwo"))
        #expect(stream.parsedFrom == 0)
    }
}

@Suite("Half-written Markdown")
struct HealedTests {
    @Test(
        "Emphasis, code and links still arriving show as they will, not as their marks",
        arguments: [
            ("Swift is **fast", "Swift is **fast**"),
            ("Use `swift bu", "Use `swift bu`"),
            ("See [Vapor](https://vap", "See Vapor"),
            ("See [Vap", "See Vap"),
            ("Both **done** and **not", "Both **done** and **not**"),
            ("A trailing **", "A trailing "),
            ("Nothing open here.", "Nothing open here."),
            ("Code `a` then **b", "Code `a` then **b**"),
            ("In code `**not bold", "In code `**not bold`"),
        ])
    func healed(_ pair: (String, String)) {
        #expect(Markdown.healed(pair.0) == pair.1)
    }
}

@Suite("Reveal")
struct RevealTests {
    private func run(_ reveal: inout Reveal, _ text: String, seconds: Double, finished: Bool = false) {
        var left = seconds
        while left > 0 {
            reveal.step(through: text, elapsed: min(0.033, left), finished: finished)
            left -= 0.033
        }
    }

    @Test("It shows whole words only, never half of one still arriving")
    func wholeWords() {
        var reveal = Reveal()
        let text = "Swift runs well on Linux and compi"
        run(&reveal, text, seconds: 2)
        #expect(reveal.shown(of: text) == "Swift runs well on Linux and ")
        run(&reveal, text, seconds: 1, finished: true)
        #expect(reveal.shown(of: text) == text)
    }

    @Test("A slow stream is shown at the reader's pace, not all at once")
    func steadyPace() {
        var reveal = Reveal()
        let text = String(repeating: "word ", count: 40)
        reveal.step(through: text, elapsed: 0.033, finished: false)
        let first = reveal.shown(of: text).count
        #expect(first > 0 && first < 40)
    }

    @Test("A big burst is caught up within about a third of a second, and the end drains quickly")
    func catchesUp() {
        var reveal = Reveal()
        let text = String(repeating: "word ", count: 400)
        run(&reveal, text, seconds: 0.5)
        #expect(reveal.shown(of: text).count > text.count * 3 / 4)
        run(&reveal, text, seconds: 0.3, finished: true)
        #expect(reveal.caughtUp(with: text))
    }

    @Test("Each step says how much it showed, so it can fade in")
    func steps() {
        var reveal = Reveal()
        let text = "One two three four five six seven eight nine ten "
        var shown = 0
        for _ in 0..<60 {
            shown += reveal.step(through: text, elapsed: 0.033, finished: true)
        }
        #expect(shown == text.count)
    }

    @Test("Accents and emoji are never split")
    func graphemes() {
        var reveal = Reveal()
        let text = "Café 👩🏽‍💻 niño "
        run(&reveal, text, seconds: 1, finished: true)
        #expect(reveal.shown(of: text) == text)
    }
}
