import Foundation
import Testing
import WebKit

@testable import Mote

/// `body` as an XHTML document: parsed as XML, where tag names keep their case.
private func xhtml(_ body: String) -> Data {
    Data(
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>XHTML</title></head><body>\(body)</body></html>
        """.utf8)
}

/// Loads `body` into `page` as `application/xhtml+xml`, which `loadHTMLString`
/// can't do, and waits until the document is parsed as XHTML and loaded.
@MainActor
private func load(xhtml body: String, into page: WebPage) async throws {
    page.webView.load(
        xhtml(body), mimeType: "application/xhtml+xml", characterEncodingName: "utf-8",
        baseURL: URL(string: "https://example.com/")!)
    for _ in 0..<200 {
        let ready = try? await page.string(
            "String(document.contentType === 'application/xhtml+xml' && document.readyState === 'complete')")
        if ready == "true" { return }
        try await Task.sleep(for: .milliseconds(50))
    }
    throw TimedOut()
}

/// Runs a called script's function body and returns its result.
@MainActor
private func call(
    _ page: WebPage, _ body: String, _ arguments: [String: Any] = [:], in world: WKContentWorld = .page
) async throws -> Any? {
    try await page.webView.callAsyncJavaScript(body, arguments: arguments, contentWorld: world)
}

/// `bench-act` as Bench calls it.
private let act = InjectedScript.call("bench-act", arguments: ["verb", "selector", "text"])

@Suite("Page scripts on XHTML pages")
@MainActor
struct XHTMLScriptTests {
    @Test("The page really is XHTML: tag names are lower case")
    func lowerCaseTagNames() async throws {
        let page = WebPage()
        try await load(xhtml: #"<input id="field"/>"#, into: page)

        #expect(try await page.string("document.getElementById('field').tagName") == "input")
    }

    @Test("The selected text is read from a focused field")
    func selectedText() async throws {
        let page = WebPage()
        try await load(xhtml: #"<p>Other text</p><input id="field" value="hello world"/>"#, into: page)
        _ = try await page.string(
            "const field = document.getElementById('field'); field.focus(); field.setSelectionRange(6, 11); 'done'")

        #expect(try await call(page, PageView.selected, in: .defaultClient) as? String == "world")
    }

    @Test("A focused password field yields nothing, even with text selected elsewhere")
    func passwordField() async throws {
        let page = WebPage()
        try await load(xhtml: #"<p id="text">Visible</p><input id="field" type="password" value="secret"/>"#, into: page)
        _ = try await page.string(
            """
            const range = document.createRange();
            range.selectNodeContents(document.getElementById('text'));
            document.getSelection().addRange(range);
            document.getElementById('field').focus();
            'done'
            """)

        #expect(try await call(page, PageView.selected, in: .defaultClient) as? String == "")
    }

    @Test("The bench types into a text area")
    func benchTypesIntoTextArea() async throws {
        let page = WebPage()
        try await load(xhtml: #"<textarea id="area"></textarea>"#, into: page)

        let said = try await call(page, act, ["verb": "type", "selector": "#area", "text": "hello"]) as? String
        #expect(said == "ok")
        #expect(try await page.string("document.getElementById('area').value") == "hello")
    }

    @Test("A right-click on an image asks for Mote's menu")
    func imageMenu() async throws {
        let inbox = MessageInbox()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(inbox, contentWorld: Web.world, name: ImageRelay.name)
        configuration.userContentController.addUserScript(
            WKUserScript(source: ImageRelay.watch, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: Web.world))
        let page = WebPage(configuration: configuration)
        let image = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='20' height='20'/%3E"
        try await load(xhtml: #"<img id="image" src="\#(image)" alt=""/>"#, into: page)

        let allowed = try await page.string(
            """
            String(document.getElementById('image').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true })))
            """)
        let messages = try await eventually { inbox.messages.isEmpty ? nil : inbox.messages }

        #expect(allowed == "false")
        #expect((messages.first as? [String: String])?["src"] == image)
    }

    @Test("The bench picks an option of a select, and fires input and change")
    func benchSelects() async throws {
        let page = WebPage()
        try await load(
            xhtml: #"<select id="size"><option value="s">Small</option><option value="l">Large</option></select>"#,
            into: page)
        _ = try await page.string(
            """
            window.heard = [];
            const size = document.getElementById('size');
            size.addEventListener('input', () => heard.push('input'));
            size.addEventListener('change', () => heard.push('change'));
            'done'
            """)

        #expect(try await call(page, act, ["verb": "type", "selector": "#size", "text": "Large"]) as? String == "ok")
        #expect(try await page.string("document.getElementById('size').value") == "l")
        #expect(try await page.string("heard.join()") == "input,change")
        let missing = try await call(page, act, ["verb": "type", "selector": "#size", "text": "Huge"]) as? String
        #expect(missing == "no option Huge in #size")
    }

    @Test("The bench refuses to type into what takes no text, and says why")
    func benchRefuses() async throws {
        let page = WebPage()
        try await load(xhtml: #"<div id="box">Box</div>"#, into: page)

        let said = try await call(page, act, ["verb": "type", "selector": "#box", "text": "hello"]) as? String
        #expect(said == "#box takes no text")
        #expect(try await page.string("document.getElementById('box').textContent") == "Box")
    }
}
