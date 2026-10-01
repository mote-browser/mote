import SwiftUI

/// Sizes the chrome is built from.
enum Metrics {
    /// A tab in the strip: its widest, the width below which only its icon
    /// shows, and its narrowest, where the row starts to scroll (see TabWidths).
    static let tabWidth: CGFloat = 224
    static let tabTitled: CGFloat = 84
    static let tabMinWidth: CGFloat = 40
    static let tabGap: CGFloat = 0
    static let pinWidth: CGFloat = 40
    /// A strip tab's height; it stands on the card's top edge.
    static let tabHeight: CGFloat = 32
    /// Where the strip's first tab starts, clear of the traffic lights.
    static let lights: CGFloat = 84
    /// The address field over a page, and the new tab's composer.
    static let fieldWidth: CGFloat = 600
    /// The sidebar's usual, narrowest and widest width.
    static let side: CGFloat = 240
    static let sideMin: CGFloat = 180
    static let sideMax: CGFloat = 440
    /// The page chat panel's usual, narrowest and widest width. It docks on the
    /// window's trailing edge, the mirror of the sidebar.
    static let chat: CGFloat = 360
    static let chatMin: CGFloat = 280
    static let chatMax: CGFloat = 560
    /// A tab in the sidebar.
    static let row: CGFloat = 32
    /// A toolbar button.
    static let button: CGFloat = 28
}

/// How things move. Springs that barely bounce, and short ease-outs for
/// hovering: quick to start, soft to land, never in the way of the next click.
enum Motion {
    /// Moving from place to place.
    static let glide = Animation.spring(response: 0.34, dampingFraction: 0.82)
    /// Appearing and going.
    static let settle = Animation.spring(response: 0.30, dampingFraction: 0.86)
    /// Small changes.
    static let quick = Animation.easeOut(duration: 0.14)
    /// Hover highlights, fast so the pointer never waits.
    static let hover = Animation.easeOut(duration: 0.1)
    /// A button sinking under the pointer and coming back.
    static let press = Animation.spring(response: 0.22, dampingFraction: 0.7)
    /// Folding the sidebar or strip away and back, and peeking it out: no
    /// overshoot, so sidebar, card and page arrive together. The traffic lights
    /// follow the same curve in Core Animation (see `SidebarFold.slide`).
    static let foldResponse: Double = 0.36
    static let fold = Animation.spring(response: foldResponse, dampingFraction: 1)
}
