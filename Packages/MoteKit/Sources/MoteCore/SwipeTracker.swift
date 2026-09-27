import CoreGraphics
import Foundation

/// Two-finger swipes on a page, turned into back and forward.
///
/// Fed the trackpad's phases and deltas, it decides when a gesture is a
/// sideways swipe, how far it has pulled, and whether letting go navigates.
/// The page gets a say first: a swipe that would scroll something on the page
/// (a carousel, a map) never navigates.
public struct SwipeTracker {
    /// How far a swipe has pulled, for the indicator at the page's edge.
    public struct Pull: Equatable, Sendable {
        /// A back swipe (from the left); false for forward.
        public var back: Bool
        /// Distance pulled in the swipe's direction, in points.
        public var travel: CGFloat
        /// Letting go now navigates.
        public var armed: Bool
        /// Let go while armed: navigation is under way.
        public var going: Bool

        public init(back: Bool, travel: CGFloat, armed: Bool, going: Bool) {
            self.back = back
            self.travel = travel
            self.armed = armed
            self.going = going
        }
    }

    public enum Effect: Equatable, Sendable {
        /// Show this pull, or hide the indicator.
        case show(Pull?)
        /// A haptic tick: crossed into (true) or out of (false) the armed range.
        case tick(armed: Bool)
        case navigate(back: Bool)
    }

    /// Pull needed to navigate on release.
    public static let arm: CGFloat = 70
    /// A quick flick navigates too: this far within `flickTime` of starting.
    public static let flick: CGFloat = 30
    public static let flickTime: TimeInterval = 0.25
    /// The indicator shows from this far.
    public static let visible: CGFloat = 6
    /// Movement before the gesture's axis is decided, and how much more
    /// sideways than vertical it must be.
    static let lockAfter: CGFloat = 6
    static let sidewaysRatio: CGFloat = 1.3
    /// Pages that never answer (PDFs, failed loads) still swipe after this.
    static let answerWait: TimeInterval = 0.18

    private var sideways: CGFloat = 0
    private var seenX: CGFloat = 0
    private var seenY: CGFloat = 0
    /// nil until decided; true for sideways.
    private var across: Bool?
    private var back = true
    /// Whether the page lets this swipe through; nil until it answers.
    private var free: Bool?
    private var started: Date?
    /// Navigated, rejected or finished: the rest of the gesture is ignored.
    private var done = false
    private var armed = false
    private var showing = false

    public init() {}

    private var travel: CGFloat { max(0, back ? sideways : -sideways) }

    /// Fingers down: a new gesture.
    public mutating func begin() {
        self = SwipeTracker()
    }

    /// Fingers moved. `canGo` says whether there is history in a direction
    /// (true for back).
    public mutating func move(dx: CGFloat, dy: CGFloat, at now: Date, canGo: (_ back: Bool) -> Bool) -> [Effect] {
        guard !done else { return [] }
        sideways += dx
        guard across == nil else { return report(at: now) }
        seenX += abs(dx)
        seenY += abs(dy)
        guard seenX + seenY > Self.lockAfter else { return [] }
        across = seenX > seenY * Self.sidewaysRatio
        back = sideways > 0
        guard across == true, canGo(back) else {
            done = true
            return []
        }
        started = now
        return report(at: now)
    }

    /// The page answered whether the swipe would scroll something of its own.
    public mutating func pageAnswered(free yes: Bool, at now: Date) -> [Effect] {
        guard across != false, !done else { return [] }
        guard yes else {
            free = false
            done = true
            return hide()
        }
        guard free == nil else { return [] }
        free = true
        return report(at: now)
    }

    /// Fingers lifted.
    public mutating func end(at now: Date) -> [Effect] {
        defer { done = true }
        guard !done, free == true else { return hide() }
        let flicked = travel >= Self.flick && started.map { now.timeIntervalSince($0) <= Self.flickTime } ?? false
        guard armed || flicked else { return hide() }
        showing = true
        return [.show(Pull(back: back, travel: travel, armed: true, going: true)), .navigate(back: back)]
    }

    /// The system took the gesture away.
    public mutating func cancel() -> [Effect] {
        done = true
        return hide()
    }

    private mutating func report(at now: Date) -> [Effect] {
        if free == nil, let started, now.timeIntervalSince(started) > Self.answerWait { free = true }
        guard free == true else { return [] }
        guard travel >= Self.visible else { return showing ? hide() : [] }
        let nowArmed = travel >= Self.arm
        var effects: [Effect] = nowArmed != armed ? [.tick(armed: nowArmed)] : []
        armed = nowArmed
        showing = true
        effects.append(.show(Pull(back: back, travel: travel, armed: nowArmed, going: false)))
        return effects
    }

    private mutating func hide() -> [Effect] {
        showing = false
        return [.show(nil)]
    }
}
