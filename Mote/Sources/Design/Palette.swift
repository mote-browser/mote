import AppKit
import SwiftUI

/// Mote's colours. Each has a light and a dark version and follows the
/// window's appearance.
enum Palette {
    /// The card the page sits on, and the ground of panels and menus.
    static let ground = Color(nsColor: NS.ground)
    /// Around the card: behind the sidebar and the tab strip.
    static let frame = Color(nsColor: NS.frame)
    /// The sidebar's active tab, raised off the frame like the card.
    static let lift = Color(nsColor: NS.lift)
    /// See-through ink for hovered and pressed things; unlike `hover` it works
    /// on any ground.
    static let veil = Color(nsColor: NS.veil)
    /// The card's outline against the frame.
    static let edge = Color(nsColor: NS.edge)
    /// Text and icons.
    static let ink = Color(nsColor: NS.ink)
    /// Secondary text.
    static let muted = Color(nsColor: NS.muted)
    /// Placeholders and quiet marks.
    static let faint = Color(nsColor: NS.faint)
    static let hairline = Color(nsColor: NS.hairline)
    /// Selected things, such as the active tab.
    static let wash = Color(nsColor: NS.wash)
    static let hover = Color(nsColor: NS.hover)
    /// Secure and not secure connections (see SiteCard.swift).
    static let safe = Color(nsColor: NS.safe)
    static let unsafe = Color(nsColor: NS.unsafe)

    /// The same colours for AppKit.
    enum NS {
        static let ground = gray(light: 1, dark: 0.11)
        static let frame = gray(light: 0.91, dark: 0.14)
        static let lift = gray(light: 1, dark: 0.26)
        static let veil = inkWash(light: 0.055, dark: 0.075)
        static let edge = inkWash(light: 0.085, dark: 0.07)
        static let ink = gray(light: 0.09, dark: 0.93)
        static let muted = gray(light: 0.55, dark: 0.58)
        static let faint = gray(light: 0.83, dark: 0.32)
        static let hairline = gray(light: 0.91, dark: 0.20)
        static let wash = gray(light: 0.937, dark: 0.175)
        static let hover = gray(light: 0.965, dark: 0.15)
        /// The traffic lights while the app is in the background, drawn by Mote.
        static let resting = gray(light: 0.80, dark: 0.30)
        static let safe = rgb(light: (0.08, 0.50, 0.24), dark: (0.29, 0.87, 0.50))
        static let unsafe = rgb(light: (0.71, 0.33, 0.04), dark: (0.98, 0.75, 0.14))

        private static func adaptive(_ make: @escaping (_ dark: Bool) -> NSColor) -> NSColor {
            NSColor(name: nil) { make($0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua) }
        }

        private static func gray(light: CGFloat, dark: CGFloat) -> NSColor {
            adaptive { NSColor(white: $0 ? dark : light, alpha: 1) }
        }

        /// Black over light, white over dark, at a given strength.
        private static func inkWash(light: CGFloat, dark: CGFloat) -> NSColor {
            adaptive { $0 ? NSColor(white: 1, alpha: dark) : NSColor(white: 0, alpha: light) }
        }

        private static func rgb(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> NSColor {
            adaptive {
                let (r, g, b) = $0 ? dark : light
                return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
            }
        }
    }
}

/// The appearance chosen in Settings.
enum Look: String, CaseIterable, Identifiable {
    case light, dark, system

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// nil follows the system.
    var appearance: NSAppearance? {
        switch self {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .system: nil
        }
    }

    /// Applies it to the whole app, so windows, panels and pages match. On the
    /// next turn of the run loop: changing it mid-animation can leave a window
    /// with an invisible layer that still takes clicks.
    func apply() {
        let wanted = appearance
        DispatchQueue.main.async {
            if NSApp.appearance?.name != wanted?.name { NSApp.appearance = wanted }
        }
    }
}
