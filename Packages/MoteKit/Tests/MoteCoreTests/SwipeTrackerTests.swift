import CoreGraphics
import Foundation
import Testing

@testable import MoteCore

@Suite("SwipeTracker")
struct SwipeTrackerTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    /// Moves in steps of `dx` (positive is a back swipe) and returns every effect.
    private func swipe(
        _ tracker: inout SwipeTracker, steps: Int, dx: CGFloat, dy: CGFloat = 0, every: TimeInterval = 0.01,
        from start: TimeInterval = 0, history: Bool = true
    ) -> [SwipeTracker.Effect] {
        (0..<steps).flatMap { i in
            tracker.move(dx: dx, dy: dy, at: t0.addingTimeInterval(start + Double(i) * every)) { _ in history }
        }
    }

    private func pulls(_ effects: [SwipeTracker.Effect]) -> [SwipeTracker.Pull?] {
        effects.compactMap { if case .show(let pull) = $0 { pull } else { nil } }
    }

    @Test("A long sideways swipe the page lets through navigates back on release")
    func navigatesBack() {
        var tracker = SwipeTracker()
        _ = swipe(&tracker, steps: 2, dx: 5)
        #expect(tracker.pageAnswered(free: true, at: t0.addingTimeInterval(0.02)).isEmpty == false)
        let moved = swipe(&tracker, steps: 10, dx: 8, from: 0.03)
        #expect(moved.contains(.tick(armed: true)))
        #expect(pulls(moved).last??.armed == true)
        let released = tracker.end(at: t0.addingTimeInterval(1))
        #expect(released.contains(.navigate(back: true)))
        #expect(pulls(released).last??.going == true)
    }

    @Test("A mostly vertical gesture is a scroll and never navigates")
    func verticalIsIgnored() {
        var tracker = SwipeTracker()
        let effects = swipe(&tracker, steps: 20, dx: 3, dy: 10)
        #expect(effects.isEmpty)
        #expect(!tracker.end(at: t0.addingTimeInterval(1)).contains(.navigate(back: true)))
    }

    @Test("A page that scrolls sideways itself keeps the swipe")
    func pageKeepsIt() {
        var tracker = SwipeTracker()
        _ = swipe(&tracker, steps: 2, dx: 5)
        #expect(tracker.pageAnswered(free: false, at: t0) == [.show(nil)])
        #expect(swipe(&tracker, steps: 20, dx: 10, from: 0.05).isEmpty)
        #expect(!tracker.end(at: t0.addingTimeInterval(1)).contains(.navigate(back: true)))
    }

    @Test("A page that never answers still swipes after a moment")
    func silentPage() {
        var tracker = SwipeTracker()
        let early = swipe(&tracker, steps: 3, dx: 10)
        #expect(pulls(early).isEmpty)
        let late = swipe(&tracker, steps: 1, dx: 10, from: 0.3)
        #expect(pulls(late).last??.travel == 40)
    }

    @Test("No history that way means no swipe")
    func noHistory() {
        var tracker = SwipeTracker()
        #expect(swipe(&tracker, steps: 20, dx: -10, history: false).isEmpty)
    }

    @Test("A short, slow pull springs back")
    func shortPull() {
        var tracker = SwipeTracker()
        _ = swipe(&tracker, steps: 2, dx: 5)
        _ = tracker.pageAnswered(free: true, at: t0)
        _ = swipe(&tracker, steps: 3, dx: 5, every: 0.2, from: 0.1)
        #expect(tracker.end(at: t0.addingTimeInterval(2)) == [.show(nil)])
    }

    @Test("A quick flick navigates before the arming distance")
    func flick() {
        var tracker = SwipeTracker()
        _ = swipe(&tracker, steps: 2, dx: -4)
        _ = tracker.pageAnswered(free: true, at: t0.addingTimeInterval(0.01))
        _ = swipe(&tracker, steps: 3, dx: -10, from: 0.02)
        #expect(tracker.end(at: t0.addingTimeInterval(0.1)).contains(.navigate(back: false)))
    }

    @Test("Pulling back under the arming distance disarms with a tick, and under the visible distance hides")
    func retract() {
        var tracker = SwipeTracker()
        _ = swipe(&tracker, steps: 2, dx: 5)
        _ = tracker.pageAnswered(free: true, at: t0)
        _ = swipe(&tracker, steps: 8, dx: 10, from: 0.01)
        let back = swipe(&tracker, steps: 1, dx: -40, from: 0.2)
        #expect(back.contains(.tick(armed: false)))
        let gone = swipe(&tracker, steps: 1, dx: -45, from: 0.3)
        #expect(gone == [.show(nil)])
    }
}

@Suite("PageFacts")
struct PageFactsTests {
    @Test("A tab is named by its given name, a pop-up's site, the title, the address, in that order")
    func labels() {
        let url = URL(string: "https://www.example.com/path")!
        #expect(TabLabel.text(name: "Mine", popup: true, address: url, title: "Title") == "Mine")
        #expect(TabLabel.text(name: "", popup: true, address: url, title: "Title") == "example.com")
        #expect(TabLabel.text(name: nil, popup: false, address: url, title: "Title") == "Title")
        #expect(TabLabel.text(name: nil, popup: false, address: url, title: "") == Address.displayString(for: url))
        #expect(TabLabel.text(name: nil, popup: false, address: nil, title: "") == "New Tab")
    }

    @Test("Monograms are the site's first letter")
    func monograms() {
        #expect(TabLabel.monogram(for: URL(string: "https://www.github.com")) == "G")
        #expect(TabLabel.monogram(for: nil) == "•")
    }

    @Test("Zoom stays between 40% and 300%")
    func zoom() {
        #expect(PageZoom.clamped(5) == 3)
        #expect(PageZoom.clamped(0.1) == 0.4)
        #expect(!PageZoom.differs(1, 1.003))
        #expect(PageZoom.isActualSize(1.005))
    }

    @Test("Reading position is a rounded fraction")
    func reading() {
        #expect(readingFraction(y: 333, of: 1000) == 0.33)
        #expect(readingFraction(y: 2000, of: 1000) == 1)
        #expect(readingFraction(y: 10, of: 0) == 0)
    }

    @Test("Safari's version follows the system from macOS 26, and ran three ahead before")
    func safari() {
        #expect(SafariVersion.shipped(withMacOS: 26) == "26.0")
        #expect(SafariVersion.shipped(withMacOS: 15) == "18.0")
    }

    @Test("A sent sign-in keeps the page's site and scheme, and expires")
    func sentSignIn() {
        let now = Date()
        let sent = SentSignIn(page: URL(string: "http://www.Shop.test/login"), user: "a", password: "b", at: now)
        #expect(sent?.host == "shop.test")
        #expect(sent?.clear == true)
        #expect(sent?.expired(at: now.addingTimeInterval(10)) == false)
        #expect(sent?.expired(at: now.addingTimeInterval(60)) == true)
        #expect(SentSignIn(page: nil, user: "a", password: "b", at: now) == nil)
    }
}
