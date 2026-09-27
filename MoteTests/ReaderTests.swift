import Testing

@testable import Mote

@Suite("Reader")
@MainActor
struct ReaderTests {
    private let paragraph = String(repeating: "Mote keeps the article and drops what was arranged around it. ", count: 3)

    @Test("Keeps the article and drops navigation and link rails")
    func extractsArticle() async throws {
        let page = WebPage()
        try await page.load(
            html: """
                <title>Page title</title>
                <nav><a href="/">Home</a> <a href="/products">Products</a> <a href="/about">About</a></nav>
                <article>
                  <h1>The headline</h1>
                  <p>\(paragraph)</p><p>\(paragraph)</p><p>\(paragraph)</p><p>\(paragraph)</p>
                </article>
                <aside>\((1...20).map { "<a href='/related/\($0)'>Related story \($0)</a>" }.joined())</aside>
                """)

        #expect(try await page.call(Reader.script) == "read")
        let text = try #require(try await page.string("document.body.innerText"))
        #expect(text.contains("The headline"))
        #expect(text.contains("Mote keeps the article"))
        #expect(!text.contains("Products"))
        #expect(!text.contains("Related story"))
    }

    @Test("A page without an article is left alone")
    func noArticle() async throws {
        let page = WebPage()
        try await page.load(html: "<p>Short.</p><a href='/'>Home</a>")

        #expect(try await page.call(Reader.script) == "none")
        #expect(try await page.string("document.body.innerText")?.contains("Short.") == true)
    }
}
