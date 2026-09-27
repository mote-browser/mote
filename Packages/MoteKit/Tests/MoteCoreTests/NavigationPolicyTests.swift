import Foundation
import Testing

@testable import MoteCore

@Suite("NavigationPolicy")
struct NavigationPolicyTests {
    typealias Request = NavigationPolicy.Request

    @Test("Ordinary loads of web and extension pages go ahead")
    func loads() {
        for scheme in ["https", "HTTP", "about", "blob", "chrome-extension"] {
            #expect(NavigationPolicy.decide(Request(scheme: scheme, clicked: false)) == .load)
        }
    }

    @Test("Other schemes go to their app")
    func handsOff() {
        #expect(NavigationPolicy.decide(Request(scheme: "mailto", clicked: true)) == .handOff)
        #expect(NavigationPolicy.decide(Request(scheme: "zoommtg", clicked: false)) == .handOff)
    }

    @Test("⌘-click opens a background tab and ⌘⇧-click a foreground one")
    func commandClicks() {
        #expect(NavigationPolicy.decide(Request(scheme: "https", clicked: true, keys: .command)) == .openTab(foreground: false))
        #expect(
            NavigationPolicy.decide(Request(scheme: "https", clicked: true, keys: [.command, .shift])) == .openTab(foreground: true))
    }

    @Test("Shift-click previews only when previews are possible, and only with shift alone")
    func peeks() {
        #expect(NavigationPolicy.decide(Request(scheme: "https", clicked: true, keys: .shift, canPeek: true)) == .peek)
        #expect(NavigationPolicy.decide(Request(scheme: "https", clicked: true, keys: .shift)) == .load)
        #expect(
            NavigationPolicy.decide(Request(scheme: "https", clicked: true, keys: [.shift, .option], canPeek: true)) == .load)
    }

    @Test("A middle-click is left to the page script")
    func middle() {
        #expect(NavigationPolicy.decide(Request(scheme: "https", clicked: true, button: 4)) == .ignore)
    }

    @Test("Modified clicks on non-web links are not opened as tabs")
    func modifiedNonWeb() {
        #expect(NavigationPolicy.decide(Request(scheme: "file", clicked: true, keys: .command)) == .load)
    }

    @Test("Only the main frame or a click may open another app; mail and phone clicks don't ask")
    func handOffRules() {
        #expect(NavigationPolicy.mayHandOff(mainFrame: true, clicked: false))
        #expect(NavigationPolicy.mayHandOff(mainFrame: false, clicked: true))
        #expect(!NavigationPolicy.mayHandOff(mainFrame: false, clicked: false))
        #expect(NavigationPolicy.handsOffQuietly(scheme: "MAILTO", clicked: true))
        #expect(!NavigationPolicy.handsOffQuietly(scheme: "tel", clicked: false))
        #expect(!NavigationPolicy.handsOffQuietly(scheme: "zoommtg", clicked: true))
    }

    @Test("Redirects are followed, attachments downloaded, unknown types downloaded")
    func responses() {
        #expect(!NavigationPolicy.downloads(status: 302, disposition: "attachment", canShow: false))
        #expect(NavigationPolicy.downloads(status: 200, disposition: " Attachment; filename=a.pdf", canShow: true))
        #expect(NavigationPolicy.downloads(status: 200, disposition: nil, canShow: false))
        #expect(!NavigationPolicy.downloads(status: nil, disposition: "inline", canShow: true))
    }

    @Test("Cancelled and interrupted loads show nothing; others explain themselves")
    func failures() {
        #expect(LoadFailure.message(domain: NSURLErrorDomain, code: NSURLErrorCancelled) == nil)
        #expect(LoadFailure.message(domain: "WebKitErrorDomain", code: 102) == nil)
        #expect(LoadFailure.message(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost) == "No site at that address.")
        #expect(LoadFailure.message(domain: NSURLErrorDomain, code: NSURLErrorTimedOut) == "The site took too long to answer.")
        #expect(LoadFailure.message(domain: NSURLErrorDomain, code: -99999) == "The page didn't load.")
    }
}

@Suite("Clippings")
struct ClippingsTests {
    @Test("Markdown links escape brackets and backslashes once")
    func markdown() {
        let url = URL(string: "https://example.com/a")!
        #expect(Clippings.markdownLink(title: #"A [b] \c"#, url: url) == #"[A \[b\] \\c](https://example.com/a)"#)
    }

    @Test("Taken file names get the next free number, before the extension")
    func freeNames() {
        let taken: Set = ["a.pdf", "a 2.pdf", "notes"]
        #expect(Clippings.freeName("b.pdf", taken: taken.contains) == "b.pdf")
        #expect(Clippings.freeName("a.pdf", taken: taken.contains) == "a 3.pdf")
        #expect(Clippings.freeName("notes", taken: taken.contains) == "notes 2")
    }
}

@Suite("Connection")
struct ConnectionTests {
    @Test("https is secure unless the certificate failed or parts came over http")
    func https() {
        #expect(Connection.of(scheme: "https", certified: true, onlySecureContent: true) == .secure)
        #expect(Connection.of(scheme: "HTTPS", certified: nil, onlySecureContent: nil) == .secure)
        #expect(Connection.of(scheme: "https", certified: true, onlySecureContent: false) == .mixed)
        #expect(Connection.of(scheme: "https", certified: false, onlySecureContent: false) == .untrusted)
    }

    @Test("http is plain; other pages have no connection to speak of")
    func others() {
        #expect(Connection.of(scheme: "http", certified: nil, onlySecureContent: nil) == .plain)
        #expect(Connection.of(scheme: "file", certified: nil, onlySecureContent: nil) == nil)
        #expect(Connection.of(scheme: nil, certified: nil, onlySecureContent: nil) == nil)
    }

    @Test("Site names drop www. and name files")
    func names() {
        #expect(Address.siteName(for: URL(string: "https://www.example.com/a")!) == "example.com")
        #expect(Address.siteName(for: URL(fileURLWithPath: "/tmp/a.html")) == "File")
        #expect(Address.siteName(for: URL(string: "about:blank")!) == "about")
    }
}
