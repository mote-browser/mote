import CoreGraphics
import Foundation

/// Swiping between spaces over the tabs: sideways in the sidebar, up and
/// down over the strip. Only a gesture clearly along that axis is claimed;
/// anything else is left to scroll. Index `count` is the new-space card
/// past the last space.
public struct SpacePager: Sendable {
    /// Space switches are at least this far apart, so fingers still moving
    /// after one don't make another.
    public static let rest: TimeInterval = 0.4
    /// Wheel clicks closer together than this are one spin: one space.
    public static let spin: TimeInterval = 0.3

    /// The spaces, and where the pager is among them.
    public var count: Int
    public var here: Int
    /// How far to swipe to switch.
    public var enough: CGFloat

    private var along: CGFloat = 0
    private var aside: CGFloat = 0
    /// nil until decided; true when the gesture runs along the spaces.
    private var claimed: Bool?
    private var restUntil = Date.distantPast
    private var lastClick = Date.distantPast

    public init(count: Int, here: Int, enough: CGFloat) {
        self.count = count
        self.here = here
        self.enough = enough
    }

    /// A new gesture. False when it comes too soon after a switch, and is to
    /// be swallowed whole.
    public mutating func begin(at now: Date) -> Bool {
        along = 0
        aside = 0
        claimed = nil
        return now > restUntil
    }

    /// Movement along the spaces and across them. Returns how far the page
    /// should follow, or nil while the gesture isn't a space swipe.
    public mutating func move(along step: CGFloat, aside sideways: CGFloat) -> CGFloat? {
        along += step
        aside += sideways
        if claimed == nil {
            guard abs(along) + abs(aside) > 6 else { return nil }
            claimed = abs(along) > abs(aside) * 1.5
        }
        guard claimed == true else { return nil }
        // Pulling past either end gives a quarter as much.
        let blocked = (along > 0 && here == 0) || (along < 0 && here == count)
        return blocked ? along / 4 : along
    }

    public var isClaimed: Bool { claimed == true }

    /// Where letting go leads: back (negative travel) is the next space.
    /// nil means stay.
    public func end(cancelled: Bool) -> Int? {
        guard claimed == true, !cancelled, abs(along) >= enough else { return nil }
        let target = here + (along < 0 ? 1 : -1)
        return (0...count).contains(target) ? target : nil
    }

    /// A mouse wheel click: the space it leads to, if it's the first of a spin
    /// and not too soon after a switch.
    public mutating func click(down: Bool, at now: Date) -> Int? {
        defer { lastClick = now }
        guard now.timeIntervalSince(lastClick) > Self.spin, now > restUntil else { return nil }
        let target = here + (down ? 1 : -1)
        return (0...count).contains(target) ? target : nil
    }

    /// A switch has started: nothing new for a moment.
    public mutating func switched(at now: Date) {
        restUntil = now.addingTimeInterval(Self.rest)
    }
}
