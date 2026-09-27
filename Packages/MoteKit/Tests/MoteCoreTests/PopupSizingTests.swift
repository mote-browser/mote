import CoreGraphics
import Testing

@testable import MoteCore

@Suite("PopupSizing")
struct PopupSizingTests {
    @Test("Fits both ways for a second, then only grows, then stops")
    func steps() {
        #expect((1...4).map(PopupSizing.step) == Array(repeating: .fit, count: 4))
        #expect((5...12).map(PopupSizing.step) == Array(repeating: .grow, count: 8))
        #expect(PopupSizing.step(13) == .stop)
    }

    @Test("Growing takes in the page, never shrinks and stays within Chrome's limits")
    func growing() {
        let now = CGSize(width: 300, height: 200)
        #expect(PopupSizing.grown(now, toTakeIn: CGSize(width: 320, height: 0)) == CGSize(width: 320, height: 200))
        #expect(PopupSizing.grown(now, toTakeIn: CGSize(width: 100, height: 100)) == now)
        #expect(PopupSizing.grown(now, toTakeIn: CGSize(width: 2000, height: 900)) == PopupSizing.largest)
    }

    @Test("Small differences don't count")
    func slack() {
        let now = CGSize(width: 300, height: 200)
        #expect(!PopupSizing.differs(CGSize(width: 302, height: 199), from: now, slack: 2))
        #expect(PopupSizing.differs(CGSize(width: 303, height: 200), from: now, slack: 2))
    }
}
