import Foundation
import Testing

@testable import MoteCore

@Suite("SearchEngine")
struct SearchEngineTests {
    @Test("Every built-in engine has a valid template", arguments: SearchEngine.allCases.filter { $0 != .custom })
    func builtInTemplates(engine: SearchEngine) {
        #expect(SearchEngine.accepts(engine.template(custom: "")))
    }

    @Test("Words are percent-encoded into the template")
    func encodesWords() {
        let url = SearchEngine.url(for: " swift & café ", template: SearchEngine.duckduckgo.template(custom: ""))
        #expect(url?.absoluteString == "https://duckduckgo.com/?q=swift%20%26%20caf%C3%A9")
    }

    @Test("Empty words make no URL")
    func emptyWords() {
        #expect(SearchEngine.url(for: "   ", template: SearchEngine.google.template(custom: "")) == nil)
    }

    @Test(
        "Custom templates must be http(s) with %s outside the host",
        arguments: [
            ("https://search.example.com/?q=%s", true),
            ("http://example.com/find/%s", true),
            ("https://example.com/?q=", false),
            ("ftp://example.com/?q=%s", false),
            ("https://%s.example.com/", false),
            ("not a url %s", false),
        ])
    func customTemplates(template: String, accepted: Bool) {
        #expect(SearchEngine.accepts(template) == accepted)
    }

    @Test("A broken custom template falls back to the standard engine")
    func customFallback() {
        #expect(SearchEngine.custom.template(custom: "nonsense") == SearchEngine.standard.template(custom: ""))
        #expect(SearchEngine.custom.name(custom: "nonsense") == SearchEngine.standard.title)
    }

    @Test("A custom engine is named after its host")
    func customName() {
        #expect(SearchEngine.custom.name(custom: "https://www.search.example.com/?q=%s") == "search.example.com")
    }
}
