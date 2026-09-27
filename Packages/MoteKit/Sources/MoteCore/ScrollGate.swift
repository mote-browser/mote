/// Which trackpad scroll events a swipe gesture takes, phase by phase. A
/// gesture must start over the right place; once taken, its momentum is
/// taken too, and one refused as too soon is swallowed whole so the page
/// underneath doesn't scroll halfway.
public struct ScrollGate: Sendable {
    public enum Phase: Sendable { case began, changed, ended, cancelled, momentum, other }

    public enum Verdict: Equatable, Sendable {
        /// Not ours: let it scroll.
        case pass
        /// Ours, and nothing to do.
        case swallow
        /// A gesture starts: call `begin(allowed:)`, then treat it as a move.
        case begin
        case move
        /// Call `coast(_:)` with whether the gesture was claimed.
        case end(cancelled: Bool)
    }

    /// Following a gesture.
    public private(set) var tracking = false
    /// Refused as too soon, and swallowed until it ends.
    public private(set) var ignoring = false
    /// Momentum after a taken gesture.
    private var coasting = false

    public init() {}

    public mutating func verdict(_ phase: Phase, over: Bool) -> Verdict {
        switch phase {
        case .momentum:
            return coasting ? .swallow : .pass
        case .began:
            coasting = false
            ignoring = false
            guard over else {
                tracking = false
                return .pass
            }
            return .begin
        case .changed:
            if ignoring { return .swallow }
            return tracking ? .move : .pass
        case .ended, .cancelled:
            if ignoring {
                ignoring = false
                coasting = true
                return .swallow
            }
            return tracking ? .end(cancelled: phase == .cancelled) : .pass
        case .other:
            return .pass
        }
    }

    public mutating func begin(allowed: Bool) {
        ignoring = !allowed
        tracking = allowed
    }

    public mutating func stop() { tracking = false }

    public mutating func coast(_ on: Bool) { coasting = on }
}
