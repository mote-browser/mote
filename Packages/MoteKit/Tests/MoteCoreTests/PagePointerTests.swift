import Foundation
import Testing

@testable import MoteCore

@Suite("LinkBubblePlace")
struct LinkBubblePlaceTests {
    @Test("Six tenths of the page, up to 640 points")
    func width() {
        #expect(LinkBubblePlace.width(page: 500) == 300)
        #expect(LinkBubblePlace.width(page: 2000) == 640)
    }

    @Test("It moves right only while the pointer is over its usual place")
    func side() {
        #expect(LinkBubblePlace.onRight(pointerX: 100, fromBottom: 20, page: 1000))
        #expect(LinkBubblePlace.onRight(pointerX: 621, fromBottom: 49, page: 1000))
        #expect(!LinkBubblePlace.onRight(pointerX: 622, fromBottom: 20, page: 1000))
        #expect(!LinkBubblePlace.onRight(pointerX: 100, fromBottom: 50, page: 1000))
    }
}

@Suite("ImageAddress")
struct ImageAddressTests {
    @Test("Web, data and blob images are usable; anything else isn't")
    func schemes() {
        for text in ["https://a.b/c.png", "HTTP://a.b/c.png", "data:image/png;base64,AA", "blob:https://a.b/1"] {
            #expect(ImageAddress.usable(text) != nil, "\(text)")
        }
        for text in ["file:///etc/passwd", "javascript:alert(1)", "", "not a url"] {
            #expect(ImageAddress.usable(text) == nil, "\(text)")
        }
    }
}
