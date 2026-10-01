import Foundation
import Testing

@testable import MoteAI

@Suite("Page instructions")
struct PageContextInstructionsTests {
    private let url = URL(string: "https://example.com/article")!

    @Test("The shared page is named by title and address, and the model is told to answer about it")
    func attached() {
        let text = Instructions.page(PageContext(url: url, title: "An article"))
        #expect(text.contains("An article"))
        #expect(text.contains("https://example.com/article"))
        #expect(text.contains("this page"))
    }

    @Test("No page, or one no longer shared, tells the model nothing")
    func absent() {
        #expect(Instructions.page(nil).isEmpty)
        var page = PageContext(url: url, title: "An article")
        page.detach()
        #expect(Instructions.page(page).isEmpty)
    }

    @Test("The page's text appears in its own block only when it was read")
    func text() {
        let without = Instructions.page(PageContext(url: url, title: "An article"))
        #expect(!without.contains("The page's text"))
        let with = Instructions.page(PageContext(url: url, title: "An article", text: "Body here"))
        #expect(with.contains("The page's text"))
        #expect(with.contains("Body here"))
    }

    @Test("The person's selection is marked apart from the page's own text")
    func selection() {
        let text = Instructions.page(PageContext(url: url, title: "An article", text: "Body", selection: "A quote"))
        #expect(text.contains("selected this text"))
        #expect(text.contains("> A quote"))
    }

    @Test("A selection over several lines is quoted line by line")
    func multiLine() {
        let text = Instructions.page(PageContext(url: url, title: "An article", selection: "one\ntwo"))
        #expect(text.contains("> one\n> two"))
    }

    @Test("A page with no title is still named by its address")
    func untitled() {
        let text = Instructions.page(PageContext(url: url, title: ""))
        #expect(text.contains("Untitled"))
        #expect(text.contains("https://example.com/article"))
    }
}
