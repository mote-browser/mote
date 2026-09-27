import Foundation
import WebKit

// Two-finger horizontal swipe navigation with an edge indicator, replacing
// WebKit's built-in page-sliding gesture.
//
// Before treating a swipe as navigation, the page reports whether any element
// under the pointer can scroll horizontally (carousels, wide tables, maps).
// The report arrives within a frame or two, before the indicator appears.

enum Swipe {
    /// Disables vertical rubber-banding while keeping it horizontally for
    /// swipe navigation, via WebKit's private `_setRubberBandingEnabled:`.
    ///
    /// CSS `overscroll-behavior-y: none` is not used because it breaks wheel
    /// scrolling on pages with non-passive wheel listeners (rdar://137757208).
    static func calm(_ web: WKWebView) {
        let set = NSSelectorFromString("_setRubberBandingEnabled:")
        guard web.responds(to: set) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, UInt) -> Void
        // _WKRectEdge bitmask of edges that keep rubber-banding: left and right only.
        let left: UInt = 1 << 0, right: UInt = 1 << 2  // CGRectMinXEdge, CGRectMaxXEdge
        unsafeBitCast(web.method(for: set), to: Setter.self)(web, set, left | right)
    }

    /// Reports whether a horizontal wheel event would scroll page content: at once
    /// when the answer changes, and at most every 100 ms while it stays the same.
    /// See Scripts/src/swipe-watch.ts.
    static let watch = InjectedScript.source("swipe-watch")
}
