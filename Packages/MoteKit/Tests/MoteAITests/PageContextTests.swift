import Foundation
import Testing

@testable import MoteAI

@Suite("Page context")
struct PageContextTests {
    private let url = URL(string: "https://example.com/article")!

    @Test("A page is shared as soon as it is taken, with only what the page gave")
    func fresh() {
        let page = PageContext(url: url, title: "  An article  ")
        #expect(page.url == url)
        #expect(page.title == "An article")
        #expect(page.text == nil)
        #expect(page.selection == nil)
        #expect(page.isAttached)
        #expect(page.isActive)
    }

    @Test("Attaching and detaching switch whether the page is shared, without losing it")
    func attached() {
        var page = PageContext(url: url, title: "An article")
        page.detach()
        #expect(!page.isAttached)
        #expect(!page.isActive)
        // Still the same page, ready to be shared again.
        #expect(page.title == "An article")
        page.attach()
        #expect(page.isAttached)
    }

    @Test("A page taken already detached stays detached")
    func takenDetached() {
        let page = PageContext(url: url, title: "An article", isAttached: false)
        #expect(!page.isActive)
    }

    @Test("Blank text and selection are no text and no selection, and the rest is trimmed")
    func blank() {
        let page = PageContext(url: url, title: "", text: "  \n ", selection: "\n\t")
        #expect(page.text == nil)
        #expect(page.selection == nil)
    }

    @Test("Text and selection are kept, trimmed")
    func trimmed() {
        let page = PageContext(url: url, title: "An article", text: "  Body  ", selection: "  quote  ")
        #expect(page.text == "Body")
        #expect(page.selection == "quote")
    }
}
