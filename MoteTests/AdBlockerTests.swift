import Testing
import WebKit

@testable import Mote

@Suite("AdBlocker", .serialized)
@MainActor
struct AdBlockerTests {
    private func compiledList() async throws -> WKContentRuleList {
        AdBlocker.shared.compile()
        return try await eventually { AdBlocker.shared.list }
    }

    @Test("The rule list compiles")
    func compiles() async throws {
        _ = try await compiledList()
        #expect(AdBlocker.shared.trouble == nil)
    }

    @Test("Known ad slots are hidden and the page's own content is not")
    func hidesAdSlots() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(try await compiledList())
        let page = WebPage(configuration: configuration)

        try await page.load(
            html: """
                <div class="adsbygoogle" id="slot">Advertisement</div>
                <div id="div-gpt-ad-123">Advertisement</div>
                <p id="article">The article.</p>
                """)

        #expect(try await page.string("getComputedStyle(document.getElementById('slot')).display") == "none")
        #expect(try await page.string("getComputedStyle(document.getElementById('div-gpt-ad-123')).display") == "none")
        #expect(try await page.string("getComputedStyle(document.getElementById('article')).display") == "block")
    }

    @Test("Pausing a site takes the list off that site's pages")
    func pausing() async throws {
        _ = try await compiledList()
        AdBlocker.shared.pause("paused.example", true)
        defer { AdBlocker.shared.pause("paused.example", false) }

        let configuration = WKWebViewConfiguration()
        AdBlocker.shared.tune(configuration.userContentController, for: "paused.example")
        let page = WebPage(configuration: configuration)
        try await page.load(html: #"<div class="adsbygoogle" id="slot">Ad</div>"#)

        #expect(try await page.string("getComputedStyle(document.getElementById('slot')).display") == "block")
    }
}
