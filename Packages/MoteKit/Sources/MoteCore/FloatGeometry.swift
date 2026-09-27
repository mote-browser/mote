import CoreGraphics
import Foundation

/// Where the floating video window goes and how it grows. Screen
/// coordinates, y up, as AppKit's.
public enum FloatGeometry {
    /// Where a flick sends the window: `margin` in from `area`'s edges. A
    /// diagonal flick (about 22° to 68°) goes to the corner it points at; a
    /// straighter one goes that way and keeps to the nearer edge the other way.
    public static func corner(for frame: CGRect, in area: CGRect, toward way: CGVector, margin: CGFloat = 12) -> CGPoint {
        let left = area.minX + margin
        let right = area.maxX - margin - frame.width
        let bottom = area.minY + margin
        let top = area.maxY - margin - frame.height
        let x = way.dx > 0 ? right : left
        let y = way.dy > 0 ? top : bottom
        let across = abs(way.dx)
        let up = abs(way.dy)
        if min(across, up) >= 0.4 * max(across, up) { return CGPoint(x: x, y: y) }
        return across >= up
            ? CGPoint(x: x, y: frame.midY > area.midY ? top : bottom) : CGPoint(x: frame.midX > area.midX ? right : left, y: y)
    }

    /// The frame at a new width: the proportions kept (no letterboxing),
    /// between `narrowest` and 85% of `screenWidth`. Around `anchor`, the point
    /// under it stays under it; without one, the top-left corner stays.
    public static func resized(
        _ frame: CGRect, toWidth width: CGFloat, narrowest: CGFloat, screenWidth: CGFloat, around anchor: CGPoint? = nil
    ) -> CGRect {
        guard frame.width > 0 else { return frame }
        let wide = min(max(narrowest, width), screenWidth * 0.85)
        let tall = wide * frame.height / frame.width
        guard let anchor else { return CGRect(x: frame.minX, y: frame.maxY - tall, width: wide, height: tall) }
        let across = (anchor.x - frame.minX) / frame.width
        let up = (anchor.y - frame.minY) / frame.height
        return CGRect(x: anchor.x - across * wide, y: anchor.y - up * tall, width: wide, height: tall)
    }

    /// How far along a glide is after `time` seconds: a critically damped
    /// spring, done at 0.6 s.
    public static func glide(at time: Double) -> Double {
        guard time < 0.6 else { return 1 }
        let omega = 15.0
        return 1 - (1 + omega * time) * exp(-omega * time)
    }

    /// A remembered frame, if it's still worth using: wide enough, and at
    /// least 60% on one of `screens`.
    public static func remembered(_ frame: CGRect, on screens: [CGRect]) -> CGRect? {
        guard frame.width > 100 else { return nil }
        let seen = screens.contains { screen in
            let overlap = screen.intersection(frame)
            return !overlap.isNull && overlap.width * overlap.height > 0.6 * frame.width * frame.height
        }
        return seen ? frame : nil
    }

    /// A two-finger swipe over the window, gathered to flick it once: a long
    /// swipe flicks straight away, a short one when the fingers lift, since
    /// swipes often start straight and turn.
    public struct Flick: Sendable {
        private var gathered = CGVector.zero
        private var flicked = false

        public init() {}

        public mutating func begin() {
            gathered = .zero
            flicked = false
        }

        /// The direction to flick in, once per swipe.
        public mutating func move(by step: CGVector, lifted: Bool) -> CGVector? {
            gathered.dx += step.dx
            gathered.dy += step.dy
            defer { if lifted { begin() } }
            let length = hypot(gathered.dx, gathered.dy)
            guard !flicked, length > 120 || (lifted && length > 20) else { return nil }
            flicked = true
            return gathered
        }
    }
}

/// Video sites where a playing video floats by itself when you leave the
/// tab. Elsewhere a playing video may be decoration, and floating waits for ⇧⌘P.
public enum VideoSites {
    /// Sites, and for shops that also stream, the part of the site with videos.
    static let known: [(host: String, path: String?)] =
        [
            "youtube.com", "youtu.be", "netflix.com", "primevideo.com", "disneyplus.com", "tv.apple.com", "twitch.tv", "vimeo.com",
            "dailymotion.com", "max.com", "hbomax.com", "canalplus.com", "mycanal.fr", "arte.tv", "france.tv", "tf1.fr", "6play.fr",
            "crunchyroll.com", "plex.tv", "peacocktv.com", "hulu.com", "paramountplus.com", "molotov.tv", "ocs.fr", "mubi.com",
            "criterionchannel.com", "ted.com", "nebula.tv", "curiositystream.com",
        ].map { ($0, nil) } + ["amazon.com", "amazon.fr", "amazon.co.uk", "amazon.de"].map { ($0, "/gp/video") }

    public static func contains(_ url: URL?) -> Bool {
        guard let url, let host = url.host()?.lowercased() else { return false }
        let path = url.path().lowercased()
        return known.contains { site in
            (host == site.host || host.hasSuffix("." + site.host)) && site.path.map(path.hasPrefix) ?? true
        }
    }
}
