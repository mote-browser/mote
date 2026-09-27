import MoteCore
import Testing
import WebKit

@testable import Mote

/// A page that hides `selectors` from document start, as Tab arms it.
@MainActor
private func hidingPage(_ selectors: [String]) -> WebPage {
    let configuration = WKWebViewConfiguration()
    configuration.userContentController.addUserScript(
        WKUserScript(
            source: ElementPicker.hiding(ElementHidingStyle.config(selectors: selectors)), injectionTime: .atDocumentStart,
            forMainFrameOnly: true, in: Web.world))
    return WebPage(configuration: configuration)
}

/// Hides `selectors` in the current document, as Tab's `applyVeils` does.
@MainActor
private func hide(_ selectors: [String], on page: WebPage) async throws {
    _ = try await page.webView.evaluateJavaScript(
        ElementPicker.hiding(ElementHidingStyle.config(selectors: selectors)), in: nil, contentWorld: Web.world)
}

@MainActor
private func display(_ page: WebPage, _ id: String) async throws -> String? {
    try await page.string("getComputedStyle(document.getElementById('\(id)')).display")
}

private let threeElements = #"<div id="banner">Cookies?</div><p id="text">Text</p><div id="other">Other</div>"#

@Suite("ElementHiding")
@MainActor
struct ElementHidingTests {
    @Test("Hidden elements are hidden from document start")
    func hidesFromStart() async throws {
        let page = hidingPage(["#banner"])
        try await page.load(
            html: #"<div id="banner">Cookies?</div><script>window.seen = getComputedStyle(banner).display</script><p id="text">Text</p>"#)

        #expect(try await page.string("window.seen") == "none")
        #expect(try await display(page, "banner") == "none")
        #expect(try await display(page, "text") == "block")
    }

    @Test("One invalid selector doesn't stop the others")
    func skipsInvalidSelectors() async throws {
        let page = hidingPage(["p[", "#banner", "::nonsense(", "#other"])
        try await page.load(html: threeElements)

        #expect(try await display(page, "banner") == "none")
        #expect(try await display(page, "other") == "none")
        #expect(try await display(page, "text") == "block")
        #expect(
            try await page.string("String(document.getElementById('\(ElementHidingStyle.styleID)').sheet.cssRules.length)") == "2")
    }

    @Test(
        "A selector can't add rules, declarations or imports of its own",
        arguments: [
            "#none {} #text { display: none !important; } #x",
            "#none } #text { display: none !important",
            "#none, #text { color: red; x:",
            "#none { } @import url(https://example.com/x.css); #x",
            "#none; #text",
            "#text { color: red }",
        ])
    func keepsSelectorsToOneRule(selector: String) async throws {
        let page = hidingPage([selector, "#banner"])
        try await page.load(html: threeElements)

        #expect(try await display(page, "text") == "block")
        #expect(try await page.string("getComputedStyle(document.getElementById('text')).color") == "rgb(0, 0, 0)")
        #expect(try await display(page, "banner") == "none")
        let sheet = "document.getElementById('\(ElementHidingStyle.styleID)').sheet"
        #expect(try await page.string("\(sheet).cssRules[0].cssText") == "#banner { display: none !important; }")
        #expect(try await page.string("String(\(sheet).cssRules.length)") == "1")
    }

    @Test("A brace inside an attribute value is only text")
    func braceInString() async throws {
        let page = hidingPage([#"[title="{ }"]"#])
        try await page.load(html: #"<p id="text" title="{ }">Text</p>"#)

        #expect(try await display(page, "text") == "none")
    }

    @Test(
        "A selector can't run script",
        arguments: [
            "`; window.escaped = 'yes'; `",
            "${window.escaped = 'yes'}",
            "\\`; window.escaped = 'yes'; //",
            "\"]}; window.escaped = 'yes'; //",
        ])
    func selectorsAreData(selector: String) async throws {
        let page = hidingPage([selector])
        try await page.load(html: "<p>Text</p>")

        let escaped = try await page.webView.evaluateJavaScript("String(window.escaped)", in: nil, contentWorld: Web.world)
        #expect(escaped as? String == "undefined")
    }

    @Test("Hiding again replaces what was hidden, and hiding nothing shows everything")
    func replaces() async throws {
        let page = hidingPage(["#banner"])
        try await page.load(html: threeElements)

        try await hide(["#other"], on: page)
        #expect(try await display(page, "banner") == "block")
        #expect(try await display(page, "other") == "none")

        try await hide([], on: page)
        #expect(try await display(page, "other") == "block")
    }
}
