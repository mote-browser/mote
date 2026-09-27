import Testing

@testable import MoteCore

@Suite("ScrollGate")
struct ScrollGateTests {
    @Test("A gesture starting elsewhere scrolls, momentum and all")
    func elsewhere() {
        var gate = ScrollGate()
        let verdicts = [
            gate.verdict(.began, over: false), gate.verdict(.changed, over: true), gate.verdict(.ended, over: true),
            gate.verdict(.momentum, over: true),
        ]
        #expect(verdicts == [.pass, .pass, .pass, .pass])
    }

    @Test("A taken gesture is followed to its end, then its momentum swallowed")
    func taken() {
        var gate = ScrollGate()
        let start = gate.verdict(.began, over: true)
        #expect(start == .begin)
        gate.begin(allowed: true)
        let move = gate.verdict(.changed, over: false)
        #expect(move == .move)
        let end = gate.verdict(.cancelled, over: false)
        #expect(end == .end(cancelled: true))
        gate.stop()
        gate.coast(true)
        let momentum = gate.verdict(.momentum, over: false)
        #expect(momentum == .swallow)
        // The next gesture starts clean.
        let next = gate.verdict(.began, over: false)
        #expect(next == .pass)
        let momentumAfter = gate.verdict(.momentum, over: false)
        #expect(momentumAfter == .pass)
    }

    @Test("A gesture refused as too soon is swallowed whole, momentum included")
    func tooSoon() {
        var gate = ScrollGate()
        _ = gate.verdict(.began, over: true)
        gate.begin(allowed: false)
        #expect(gate.ignoring && !gate.tracking)
        let verdicts = [gate.verdict(.changed, over: true), gate.verdict(.ended, over: true), gate.verdict(.momentum, over: true)]
        #expect(verdicts == [.swallow, .swallow, .swallow])
        #expect(!gate.ignoring)
    }

    @Test("Unclaimed endings leave momentum to the page")
    func unclaimed() {
        var gate = ScrollGate()
        _ = gate.verdict(.began, over: true)
        gate.begin(allowed: true)
        let end = gate.verdict(.ended, over: true)
        #expect(end == .end(cancelled: false))
        gate.stop()
        gate.coast(false)
        let momentum = gate.verdict(.momentum, over: true)
        #expect(momentum == .pass)
        let other = gate.verdict(.other, over: true)
        #expect(other == .pass)
    }
}
