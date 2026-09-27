import CoreGraphics

/// Widths of the tabs in the strip: every unpinned tab gets the same width,
/// shrinking from `widest` as tabs are added, down to `narrowest`, where the
/// row starts to scroll. Below `titled` a tab shows only its icon.
public struct TabWidths: Equatable, Sendable {
    public var widest: CGFloat
    public var narrowest: CGFloat
    public var titled: CGFloat
    /// Width of a pinned tab.
    public var pinned: CGFloat
    /// Space between two tabs.
    public var gap: CGFloat

    public init(widest: CGFloat, narrowest: CGFloat, titled: CGFloat, pinned: CGFloat, gap: CGFloat) {
        self.widest = widest
        self.narrowest = narrowest
        self.titled = titled
        self.pinned = pinned
        self.gap = gap
    }

    /// Width of each unpinned tab when `count` tabs, `pins` of them pinned, share `room`.
    public func loose(room: CGFloat, pins: Int, count: Int) -> CGFloat {
        let loose = count - pins
        guard loose > 0 else { return widest }
        let spent = CGFloat(pins) * pinned + CGFloat(max(0, count - 1)) * gap
        return max(narrowest, min(widest, (room - spent) / CGFloat(loose)))
    }

    /// Width of the whole row of tabs.
    public func row(room: CGFloat, pins: Int, count: Int) -> CGFloat {
        let each = loose(room: room, pins: pins, count: count)
        return CGFloat(pins) * pinned + CGFloat(count - pins) * each + CGFloat(max(0, count - 1)) * gap
    }

    /// Whether the row is wider than the room and has to scroll.
    public func overflows(room: CGFloat, pins: Int, count: Int) -> Bool {
        row(room: room, pins: pins, count: count) > room + 0.5
    }

    /// Whether a tab this wide has room for its title.
    public func showsTitle(at width: CGFloat) -> Bool {
        width >= titled
    }
}
