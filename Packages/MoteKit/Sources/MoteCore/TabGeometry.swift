import CoreGraphics
import Foundation

/// Where the places of a row, a column or a grid filled row by row sit,
/// from the first one's.
public struct Lattice: Equatable, Sendable {
    public let columns: Int
    /// From one place to the next across and down; zero along an axis the
    /// places don't follow.
    public let step: CGSize

    public init(columns: Int, step: CGSize) {
        self.columns = max(1, columns)
        self.step = step
    }

    public static func row(step: CGFloat) -> Lattice { Lattice(columns: .max, step: CGSize(width: step, height: 0)) }
    public static func column(step: CGFloat) -> Lattice { Lattice(columns: 1, step: CGSize(width: 0, height: step)) }

    public func origin(_ place: Int) -> CGSize {
        CGSize(width: CGFloat(place % columns) * step.width, height: CGFloat(place / columns) * step.height)
    }

    /// Only the part of `travel` along the axes the places follow.
    func along(_ travel: CGSize) -> CGSize {
        CGSize(width: step.width > 0 ? travel.width : 0, height: step.height > 0 ? travel.height : 0)
    }

    /// The place nearest to where `travel` has taken the one at `start`: the
    /// next once past halfway, never past the edges, and within `places`, the
    /// held tab's section.
    public func target(from start: Int, travel: CGSize, within places: Range<Int>) -> Int {
        guard !places.isEmpty else { return start }
        let column = start % columns + (step.width > 0 ? Int((travel.width / step.width).rounded()) : 0)
        let row = start / columns + (step.height > 0 ? Int((travel.height / step.height).rounded()) : 0)
        let lastRow = (places.upperBound - 1) / columns
        let place = min(max(0, row), lastRow) * columns + min(max(0, column), columns - 1)
        return min(max(place, places.lowerBound), places.upperBound - 1)
    }
}

/// A tab dragged to a new place. The held tab follows the pointer and the
/// tabs it passes step aside to make room, by offsets alone: the order, and
/// so the layout, changes only once it is let go. Reordering mid-drag moved
/// the held tab to its new place with the list's animation while its offset
/// made up for it at once, so it jumped back a place each time it passed one.
public struct ReorderDrag<ID: Hashable>: Equatable {
    public let id: ID
    /// Its place when picked up.
    public let start: Int
    /// The place it would take if let go now.
    public private(set) var target: Int
    public private(set) var travel = CGSize.zero
    /// Let go, with the order changed: it eases from where it was dropped
    /// into its new place.
    public private(set) var landed = false

    public init(id: ID, start: Int) {
        self.id = id
        self.start = start
        target = start
    }

    /// The pointer has gone `travel` from where the tab was picked up.
    public mutating func follow(_ travel: CGSize, in lattice: Lattice, within places: Range<Int>) {
        self.travel = lattice.along(travel)
        target = lattice.target(from: start, travel: self.travel, within: places)
    }

    /// Let go. Whoever holds the order moves the tab to `target` along with this.
    public mutating func land() {
        landed = true
    }

    /// Animate home while keeping the held tab above its neighbours until arrival.
    public mutating func settle(in lattice: Lattice) {
        guard landed else { return }
        travel = lattice.origin(target) - lattice.origin(start)
    }

    /// How far the tab `other`, at `index` in the current order, sits from its place.
    public func offset(of other: ID, at index: Int, in lattice: Lattice) -> CGSize {
        if other == id {
            guard landed else { return travel }
            let moved = lattice.origin(target) - lattice.origin(start)
            return travel - moved
        }
        guard !landed else { return .zero }
        let place =
            start < index && index <= target
            ? index - 1
            : target <= index && index < start
                ? index + 1
                : index
        return lattice.origin(place) - lattice.origin(index)
    }
}

extension CGSize {
    fileprivate static func - (a: CGSize, b: CGSize) -> CGSize { CGSize(width: a.width - b.width, height: a.height - b.height) }
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
