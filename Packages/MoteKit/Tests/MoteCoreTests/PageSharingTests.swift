import Foundation
import Testing

@testable import MoteCore

@Suite("PageSharing")
struct PageSharingTests {
    private let article = URL(string: "https://example.com/article")!

    @Test("A web or file page can be shared; a blank tab, a fragment-only page and an internal one cannot")
    func shareable() {
        #expect(PageSharing.canShare(article))
        #expect(PageSharing.canShare(URL(string: "http://example.com/")!))
        #expect(PageSharing.canShare(URL(string: "file:///Users/me/notes.html")!))
        #expect(!PageSharing.canShare(nil))
        #expect(!PageSharing.canShare(URL(string: "about:blank")!))
        #expect(!PageSharing.canShare(URL(string: "data:text/html,<p>hi</p>")!))
        #expect(!PageSharing.canShare(URL(string: "blob:https://example.com/1234")!))
    }

    @Test("The same page with a different fragment is the same page")
    func samePage() {
        #expect(PageSharing.isSamePage(article, article))
        #expect(PageSharing.isSamePage(article, URL(string: "https://example.com/article#section")!))
        #expect(PageSharing.isSamePage(URL(string: "https://example.com/article#a")!, URL(string: "https://example.com/article#b")!))
        #expect(!PageSharing.isSamePage(article, URL(string: "https://example.com/other")!))
        #expect(!PageSharing.isSamePage(article, URL(string: "https://other.com/article")!))
        #expect(!PageSharing.isSamePage(nil, article))
        #expect(!PageSharing.isSamePage(article, nil))
    }

    @Test("A chat on screen takes up a page it can read, unless it already holds that same page")
    func takesUp() {
        let other = URL(string: "https://example.com/other")!
        #expect(!PageSharing.takesUp(article, chatting: false, holding: nil))
        #expect(PageSharing.takesUp(article, chatting: true, holding: nil))
        #expect(!PageSharing.takesUp(article, chatting: true, holding: article))
        #expect(PageSharing.takesUp(article, chatting: true, holding: other))
        #expect(!PageSharing.takesUp(article, chatting: true, holding: URL(string: "https://example.com/article#part")!))
        #expect(!PageSharing.takesUp(URL(string: "about:blank")!, chatting: true, holding: nil))
        #expect(!PageSharing.takesUp(nil, chatting: true, holding: nil))
    }

    @Test("Moving within a shared page keeps it; moving away, or to nowhere, lets it go; nothing shared detaches nothing")
    func detaches() {
        #expect(!PageSharing.detaches(from: nil, movingTo: article))
        #expect(!PageSharing.detaches(from: article, movingTo: URL(string: "https://example.com/article#later")!))
        #expect(PageSharing.detaches(from: article, movingTo: URL(string: "https://example.com/other")!))
        #expect(PageSharing.detaches(from: article, movingTo: nil))
    }
}
