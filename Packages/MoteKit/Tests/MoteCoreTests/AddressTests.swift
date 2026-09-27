import Foundation
import Testing

@testable import MoteCore

@Suite("Address")
struct AddressTests {
    @Test(
        "Hosts get https",
        arguments: [
            ("example.com", "https://example.com"),
            ("example.com/path?q=1#top", "https://example.com/path?q=1#top"),
            ("sub.example.co.uk", "https://sub.example.co.uk"),
            ("  example.com  ", "https://example.com"),
        ])
    func hosts(typed: String, expected: String) {
        #expect(Address.url(from: typed)?.absoluteString == expected)
    }

    @Test(
        "Local addresses get http",
        arguments: [
            ("localhost:3000", "http://localhost:3000"),
            ("app.localhost", "http://app.localhost"),
            ("127.0.0.1:8080/api", "http://127.0.0.1:8080/api"),
            ("192.168.1.20", "http://192.168.1.20"),
            ("10.0.0.1", "http://10.0.0.1"),
        ])
    func localAddresses(typed: String, expected: String) {
        #expect(Address.url(from: typed)?.absoluteString == expected)
    }

    @Test(
        "Explicit supported schemes are kept",
        arguments: [
            "https://example.com", "http://example.com", "file:///tmp/a.html", "about:blank", "data:text/html,hi",
        ])
    func explicitSchemes(typed: String) {
        #expect(Address.url(from: typed)?.absoluteString == typed)
    }

    @Test(
        "Text that isn't a place is refused",
        arguments: [
            "", "   ", "hello world", "todo", "1.2.3", "someone@example.com",
            "mailto://someone@example.com", "ftp://example.com", "-bad.com", "bad-.com", "example.c",
        ])
    func refused(typed: String) {
        #expect(Address.url(from: typed) == nil)
    }

    @Test(
        "Display string drops scheme, www and a bare slash",
        arguments: [
            ("https://www.example.com/", "example.com"),
            ("https://example.com/docs/page", "example.com/docs/page"),
            ("http://localhost:3000", "localhost"),
            ("about:blank", "about:blank"),
        ])
    func displayString(url: String, expected: String) throws {
        let url = try #require(URL(string: url))
        #expect(Address.displayString(for: url) == expected)
    }

    @Test("Site settings are kept under the host without www")
    func siteHost() {
        #expect(Address.siteHost(of: URL(string: "https://WWW.Example.com/a")) == "example.com")
        #expect(Address.siteHost(of: URL(string: "https://mail.example.com")) == "mail.example.com")
        #expect(Address.siteHost(of: URL(string: "about:blank")) == nil)
        #expect(Address.siteHost(of: nil) == nil)
    }
}
