import CoreGraphics
import Foundation

/// An extension popup's size, as Chrome does it: fitted to its page, from
/// 25 × 25 up to 800 × 600 points.
public enum PopupSizing {
    public static let largest = CGSize(width: 800, height: 600)
    /// What a new extension's popup opens at, before it's measured.
    public static let first = CGSize(width: 360, height: 240)
    /// How often the page is measured again after it loads, and for how long.
    public static let interval: TimeInterval = 0.25
    public static let ticks = 12

    public enum Step: Equatable, Sendable {
        /// Fit the page, larger or smaller.
        case fit
        /// Only grow: shrinking back and forth would make the popup shake.
        case grow
        case stop
    }

    /// For the first second the popup follows its page both ways; then,
    /// until `ticks`, it only grows.
    public static func step(_ tick: Int) -> Step {
        switch tick {
        case ...4: .fit
        case ...ticks: .grow
        default: .stop
        }
    }

    /// Whether `wanted` differs from `now` by more than `slack` either way.
    public static func differs(_ wanted: CGSize, from now: CGSize, slack: CGFloat) -> Bool {
        abs(wanted.width - now.width) > slack || abs(wanted.height - now.height) > slack
    }

    /// The popup grown to take in the page's `extent`, within the largest size.
    public static func grown(_ now: CGSize, toTakeIn extent: CGSize) -> CGSize {
        CGSize(width: min(largest.width, max(now.width, extent.width)), height: min(largest.height, max(now.height, extent.height)))
    }

    /// Pressing a button closes its popup on mouse-down, before the press
    /// lands on mouse-up; a press this soon after only closes it.
    public static let reopenGuard: TimeInterval = 1.5
}
