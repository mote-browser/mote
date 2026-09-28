import Foundation
import Testing

@testable import MoteAI

@Suite("Sources")
struct SourceTests {
    private func source(_ url: String, _ title: String = "") -> Source { Source(url: URL(string: url)!, title: title) }

    @Test("The same page reads the same however its address is dressed")
    func canonical() {
        let plain = source("https://swift.org/blog/swift-6.4")
        #expect(source("https://www.Swift.org/blog/swift-6.4/").id == plain.id)
        #expect(source("https://swift.org/blog/swift-6.4#highlights").id == plain.id)
        #expect(source("https://swift.org/blog/swift-6.4?utm_source=openai&utm_medium=x").id == plain.id)
        #expect(source("http://swift.org/blog/swift-6.4").id == plain.id)
        #expect(source("https://swift.org/blog/swift-6.4?page=2").id != plain.id)
    }

    @Test("The site is the host without www")
    func site() {
        #expect(source("https://www.theverge.com/a").site == "theverge.com")
        #expect(source("https://en.wikipedia.org/wiki/Swift").site == "en.wikipedia.org")
    }

    @Test("The brand is the site's own name, without subdomains or the ending")
    func brand() {
        #expect(source("https://www.swift.org/blog").brand == "swift")
        #expect(source("https://en.wikipedia.org/wiki/X").brand == "wikipedia")
        #expect(source("https://news.bbc.co.uk/x").brand == "bbc")
        #expect(source("http://localhost:8080/x").brand == "localhost")
    }

    @Test("A source without a title is named after its page, or else its site")
    func untitled() {
        #expect(source("https://www.swift.org/", "").name == "swift.org")
        #expect(source("https://en.wikipedia.org/wiki/Swift_(programming_language)", "").name == "Swift (programming language)")
        #expect(source("https://www.swift.org/blog/swift-6.4-released/", "").name == "swift 6.4 released")
        #expect(source("https://example.com/p?id=3", "").name == "example.com")
        #expect(source("https://www.swift.org/blog/", "Blog | Swift.org").name == "Blog | Swift.org")
    }

    @Test("Citations are the reply's links to web pages, numbered as they first appear")
    func citations() {
        let text = """
            Swift 6.4 is out [swift.org](https://www.swift.org/blog/swift-6.4-released/). It brings Span \
            ([dev.to](https://dev.to/a)) and more [Swift.org](https://swift.org/blog/swift-6.4-released) \
            — see [the docs](mailto:x@y.z) and ![chart](https://img.example/c.png).
            """
        let cited = Citations.order(in: text)
        #expect(
            cited == [
                Source.key(for: URL(string: "https://swift.org/blog/swift-6.4-released")!),
                Source.key(for: URL(string: "https://dev.to/a")!),
            ])
    }

    @Test("Links inside code aren't citations")
    func codeLinks() {
        let text = "Use `[a](https://a.com)` like this:\n```\n[b](https://b.com)\n```\nThen [c](https://c.com)."
        #expect(Citations.order(in: text) == [Source.key(for: URL(string: "https://c.com")!)])
    }

    @Test("A reply's sources list cited ones first, in citation order, then the rest")
    func arranged() {
        let sources = [source("https://a.com"), source("https://b.com"), source("https://c.com")]
        let text = "B says so [b](https://b.com), and C too [c](https://c.com)."
        let arranged = Citations.arrange(sources, for: text)
        #expect(arranged.map(\.source.site) == ["b.com", "c.com", "a.com"])
        #expect(arranged.map(\.number) == [1, 2, nil])
    }

    @Test("A cited page nobody reported as a source still counts as one")
    func citedOnly() {
        let arranged = Citations.arrange([], for: "See [d](https://d.com/x).")
        #expect(arranged.map(\.source.url.absoluteString) == ["https://d.com/x"])
        #expect(arranged.first?.number == 1)
        #expect(arranged.first?.source.title == "d")
    }

    @Test("Addresses with parentheses in them are cited whole")
    func parentheses() {
        let text = "Swift [wikipedia](https://en.wikipedia.org/wiki/Swift_(programming_language)) (see also [a](https://a.com))."
        #expect(
            Citations.links(in: text).map(\.url.absoluteString) == [
                "https://en.wikipedia.org/wiki/Swift_(programming_language)", "https://a.com",
            ])
    }

    @Test(
        "A closing list of the sources the reply links is left out of what the chat shows",
        arguments: [
            "Answer [a](https://a.com).\n\nSources:\n- [A](https://a.com)\n- [B page](https://b.com/x)",
            "Answer [a](https://a.com).\n\n**Sources:**\n\n1. [A](https://a.com)\n2. [B](https://b.com)",
            "Answer [a](https://a.com).\n\n## Fuentes\n* [A](https://a.com) — the site's page\n",
            "Answer [a](https://a.com).\n\nReferences: [A](https://a.com), [B](https://b.com)",
        ])
    func sourceList(text: String) {
        #expect(Citations.shown(text) == "Answer [a](https://a.com).")
    }

    @Test("A list that isn't only links, or isn't at the end, stays")
    func keptLists() {
        let steps = "Do this:\n\nSources:\n- open [a](https://a.com) and then think about it for a while\n- rest"
        #expect(Citations.shown(steps) == steps)
        let middle = "Sources:\n- [A](https://a.com)\n\nThen more text."
        #expect(Citations.shown(middle) == middle)
    }
}
