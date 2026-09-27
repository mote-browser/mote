import CoreGraphics
import Foundation
import Testing

@testable import MoteCore

@Suite("SpacePager")
struct SpacePagerTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    @Test("A gesture along the spaces is claimed and follows the fingers")
    func claims() {
        var pager = SpacePager(count: 3, here: 1, enough: 50)
        let started = pager.begin(at: t0)
        let small = pager.move(along: -4, aside: 0)
        let more = pager.move(along: -10, aside: 1)
        #expect(started)
        #expect(small == nil)
        #expect(more == -14)
        #expect(pager.isClaimed)
        #expect(pager.end(cancelled: false) == nil)
        _ = pager.move(along: -40, aside: 0)
        #expect(pager.end(cancelled: false) == 2)
    }

    @Test("A gesture mostly across is left alone")
    func declines() {
        var pager = SpacePager(count: 3, here: 1, enough: 50)
        _ = pager.begin(at: t0)
        let across = pager.move(along: 5, aside: 9)
        let later = pager.move(along: 200, aside: 0)
        #expect(across == nil)
        #expect(later == nil)
        #expect(pager.end(cancelled: false) == nil)
    }

    @Test("Past either end it pulls a quarter as far, and goes nowhere")
    func ends() {
        var first = SpacePager(count: 3, here: 0, enough: 50)
        _ = first.begin(at: t0)
        let back = first.move(along: 80, aside: 0)
        #expect(back == 20)
        #expect(first.end(cancelled: false) == nil)
        var card = SpacePager(count: 3, here: 3, enough: 50)
        _ = card.begin(at: t0)
        let on = card.move(along: -80, aside: 0)
        #expect(on == -20)
        #expect(card.end(cancelled: false) == nil)
    }

    @Test("A cancelled gesture stays")
    func cancelled() {
        var pager = SpacePager(count: 3, here: 1, enough: 50)
        _ = pager.begin(at: t0)
        _ = pager.move(along: 100, aside: 0)
        #expect(pager.end(cancelled: true) == nil)
        #expect(pager.end(cancelled: false) == 0)
    }

    @Test("Right after a switch, new gestures and wheel clicks are held off")
    func resting() {
        var pager = SpacePager(count: 3, here: 1, enough: 50)
        pager.switched(at: t0)
        let tooSoon = pager.begin(at: at(0.2))
        let later = pager.begin(at: at(0.5))
        var wheel = SpacePager(count: 3, here: 1, enough: 50)
        wheel.switched(at: t0)
        let click = wheel.click(down: true, at: at(0.1))
        #expect(!tooSoon)
        #expect(later)
        #expect(click == nil)
    }

    @Test("A wheel spin moves one space however many clicks it has")
    func wheel() {
        var pager = SpacePager(count: 3, here: 1, enough: 50)
        let first = pager.click(down: true, at: t0)
        let same = pager.click(down: true, at: at(0.1))
        let next = pager.click(down: false, at: at(1))
        #expect(first == 2)
        #expect(same == nil)
        #expect(next == 0)
    }
}
