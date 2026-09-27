import CoreGraphics
import Foundation

/// Where a dragged tab lands.
public enum Reorder {
    /// In a row or column: `travel` along it, `step` from one place to the next.
    public static func target(from start: Int, travel: CGFloat, step: CGFloat, count: Int) -> Int {
        guard count > 0, step > 0 else { return start }
        return min(max(0, start + Int((travel / step).rounded())), count - 1)
    }

    /// In a grid filled row by row, whose cells may be wider than tall.
    public static func target(from start: Int, travel: CGSize, step: CGSize, columns: Int, count: Int) -> Int {
        guard count > 0, columns > 0, step.width > 0, step.height > 0 else { return start }
        let moved = Int((travel.height / step.height).rounded()) * columns + Int((travel.width / step.width).rounded())
        return min(max(0, start + moved), count - 1)
    }

    /// How far a dragged grid cell sits from its current slot: the pointer's
    /// travel less the slots it has already moved through.
    public static func offset(travel: CGSize, step: CGSize, columns: Int, from start: Int, now index: Int) -> CGSize {
        guard columns > 0 else { return travel }
        return CGSize(
            width: travel.width - CGFloat(index % columns - start % columns) * step.width,
            height: travel.height - CGFloat(index / columns - start / columns) * step.height)
    }
}

/// The sidebar's pinned tabs: a grid of at least three columns that grows
/// wider past six pins, keeping to two rows.
public struct PinGrid: Equatable, Sendable {
    public static let tallest: CGFloat = 36

    public let columns: Int
    public let cell: CGSize
    public let gap: CGFloat

    /// For `count` pins across `width` (the sidebar less its margins).
    public init(count: Int, width: CGFloat, gap: CGFloat) {
        columns = max(3, (count + 1) / 2)
        let cellWidth = max(20, (width - CGFloat(columns - 1) * gap) / CGFloat(columns))
        // Wide cells become short buttons rather than big squares.
        cell = CGSize(width: cellWidth, height: min(Self.tallest, cellWidth))
        self.gap = gap
    }

    public func rows(_ count: Int) -> Int { (count + columns - 1) / columns }

    /// The grid's height for `count` pins.
    public func height(_ count: Int) -> CGFloat {
        let rows = rows(count)
        return rows == 0 ? 0 : CGFloat(rows) * cell.height + CGFloat(rows - 1) * gap
    }

    public var step: CGSize { CGSize(width: cell.width + gap, height: cell.height + gap) }
}

/// The tab strip across the top.
public enum TabStrip {
    /// The room tabs have: the strip less the traffic lights, the spaces dot,
    /// the new-tab button, some empty strip to drag the window by, and the
    /// active tab's feet at both ends.
    public static func room(strip: CGFloat, lights: CGFloat, dot: CGFloat, plus: CGFloat, dragRoom: CGFloat, foot: CGFloat) -> CGFloat {
        max(0, strip - lights - dot - plus - dragRoom - 2 * foot)
    }
}

/// A SwiftUI spring (response, damping fraction) as the mass, stiffness and
/// damping Core Animation's springs take, so both move alike.
public struct SpringCurve: Equatable, Sendable {
    public let mass: CGFloat
    public let stiffness: CGFloat
    public let damping: CGFloat

    public init(response: Double, dampingFraction: Double) {
        mass = 1
        stiffness = pow(2 * .pi / response, 2)
        damping = 4 * .pi * dampingFraction / response
    }
}

/// The disc at the page's edge during a swipe back or forward. It follows
/// the fingers directly; a spring would lag behind a quick flick.
public struct SwipeDisc: Equatable, Sendable {
    /// How full its ring is, 0 to 1; full when letting go would navigate.
    public let progress: CGFloat
    public let scale: CGFloat
    /// How far in from the edge it sits.
    public let inset: CGFloat

    public init(travel: CGFloat, going: Bool) {
        progress = min(1, travel / 110)
        scale = going ? 1.08 : 0.86 + 0.14 * progress
        // However far the swipe goes, the disc eases to a stop.
        let reach = 150 * (1 - exp(-travel / 110))
        inset = 10 + reach * 0.2 + (going ? 12 : 0)
    }
}

/// What a double click on the title bar does, from the user's setting.
public enum TitleBarClick: Equatable, Sendable {
    case zoom, minimize, nothing

    /// From AppleActionOnDoubleClick; unset means zoom.
    public init(setting: String?) {
        switch setting {
        case "Minimize": self = .minimize
        case "None": self = .nothing
        default: self = .zoom
        }
    }
}
