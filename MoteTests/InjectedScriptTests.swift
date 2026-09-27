import Testing
import WebKit

@testable import Mote

@Suite("Injected scripts")
@MainActor
struct InjectedScriptTests {
    @Test("Every built script is in the app bundle")
    func bundled() {
        for name in ["reader", "status-line", "autoscroll"] {
            #expect(!InjectedScript.source(name).isEmpty)
        }
    }

    @Test("The status line reports the hovered link once, and clears it on leaving")
    func statusLine() async throws {
        let inbox = MessageInbox()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(inbox, name: HoveredLink.name)
        configuration.userContentController.addUserScript(
            WKUserScript(source: HoveredLink.script, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        )
        let page = WebPage(configuration: configuration)
        try await page.load(html: #"<a id="link" href="/docs">Docs</a><p id="text">Text</p>"#)

        _ = try await page.string(
            """
            const over = (id) => document.getElementById(id).dispatchEvent(new MouseEvent('mouseover', { bubbles: true, composed: true }));
            over('link'); over('link'); over('text');
            'done'
            """)
        let messages = try await eventually { inbox.messages.count >= 2 ? inbox.messages : nil }

        #expect(messages as? [String] == ["https://example.com/docs", ""])
    }

    @Test("A middle click starts autoscroll with its badge, and Escape stops it")
    func autoscroll() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(
            WKUserScript(source: AutoScroll.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        let page = WebPage(configuration: configuration)
        try await page.load(html: #"<div style="height: 5000px">Long page</div>"#)

        let started = try await page.string(
            """
            document.body.dispatchEvent(new MouseEvent('mousedown', { button: 1, bubbles: true, clientX: 200, clientY: 200 }));
            document.documentElement.style.cursor
            """)
        #expect(started == "all-scroll")

        let stopped = try await page.string(
            """
            dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
            document.documentElement.style.cursor
            """)
        #expect(stopped == "")
    }

    @Test("A middle click on a link is left to the link")
    func autoscrollIgnoresLinks() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(
            WKUserScript(source: AutoScroll.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        let page = WebPage(configuration: configuration)
        try await page.load(html: #"<a id="link" href="/next">Next</a>"#)

        let cursor = try await page.string(
            """
            document.getElementById('link').dispatchEvent(new MouseEvent('mousedown', { button: 1, bubbles: true }));
            document.documentElement.style.cursor
            """)
        #expect(cursor == "")
    }
}
