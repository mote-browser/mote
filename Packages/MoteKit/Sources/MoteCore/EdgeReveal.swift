import CoreGraphics

/// Decides when folded tabs slide out over the page and back: the pointer
/// reaching the window's edge brings them out, and leaving them puts them away
/// after a short grace. Kept apart from the view so the rules can be tested
/// without moving a real pointer.
public enum EdgeReveal {
    /// Distance from the edge, in points, that brings the tabs out.
    public static let edge: CGFloat = 6
    /// How long the pointer must rest on the edge first, when it does (see `step`).
    public static let dwell: Double = 0.15
    /// Delay before the tabs go away once the pointer has left them: barely
    /// felt, but enough that grazing their edge on the way past doesn't flicker
    /// them shut and open again.
    public static let grace: Double = 0.1

    /// Where the pointer is.
    public struct Pointer: Equatable, Sendable {
        /// Inside the window's frame.
        public var inWindow: Bool
        /// The topmost window under the pointer is the browser window, not another
        /// app's window above it.
        public var onWindow: Bool
        /// Over another of the app's own windows, such as a menu opened from the tabs.
        public var onOwnPanel: Bool
        /// Distance from the edge the tabs come out of.
        public var distance: CGFloat

        public init(inWindow: Bool, onWindow: Bool, onOwnPanel: Bool, distance: CGFloat) {
            self.inWindow = inWindow
            self.onWindow = onWindow
            self.onOwnPanel = onOwnPanel
            self.distance = distance
        }
    }

    public enum Step: Equatable, Sendable {
        /// Bring the tabs out now, cancelling a pending hide.
        case show
        /// Bring them out after `dwell`, unless the pointer moves on first.
        case showSoon
        /// Put them away after `grace`, unless the pointer comes back first.
        case hideSoon
        /// Nothing to do; a pending show is cancelled.
        case pass
    }

    /// - Parameters:
    ///   - peeking: the tabs are out over the page.
    ///   - reach: how far from the edge the peeking tabs extend.
    ///   - waits: whether reaching the edge waits for `dwell` first. The top edge
    ///     always waits, since it is crossed on the way to the menu bar.
    public static func step(_ pointer: Pointer, peeking: Bool, reach: CGFloat, waits: Bool) -> Step {
        if peeking {
            let over = pointer.onOwnPanel || (pointer.onWindow && pointer.inWindow && pointer.distance < reach)
            return over ? .show : .hideSoon
        }
        guard pointer.inWindow, pointer.onWindow, pointer.distance < edge else { return .pass }
        return waits ? .showSoon : .show
    }
}
