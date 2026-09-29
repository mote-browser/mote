import AppKit
import MoteAI
import Observation

/// Shows a reply as it streams in: words at a reader's pace (see `Reveal`),
/// each fading in as it appears. It ticks only while behind; a reply already
/// there when the chat opens shows at once.
@MainActor
@Observable
final class Typewriter {
    /// Words shown lately, oldest first: how many characters, and when.
    struct Fresh: Equatable {
        var count: Int
        var at: TimeInterval
    }

    /// How long a word takes to fade in.
    static let fade: TimeInterval = 0.3

    private(set) var shown = ""
    private(set) var fresh: [Fresh] = []

    @ObservationIgnored private var reveal = Reveal()
    @ObservationIgnored private var target = ""
    @ObservationIgnored private var finished = true
    @ObservationIgnored private var ticking: Task<Void, Never>?
    @ObservationIgnored private var started = false

    /// Follows the reply's text as it grows; `finished` once it's done.
    func follow(_ text: String, finished: Bool) {
        target = text
        self.finished = finished
        // The first look at a reply, or one that changed rather than grew
        // (its closing list of sources taken off), shows it as it is.
        if !started || !text.hasPrefix(shown) || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            started = true
            reveal.showAll(text)
            shown = text
            fresh = []
            return
        }
        guard ticking == nil, !reveal.caughtUp(with: text) else { return }
        ticking = Task { [weak self] in
            var last = ContinuousClock.now
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                let now = ContinuousClock.now
                let elapsed = (now - last) / .seconds(1)
                last = now
                guard self.tick(elapsed) else { break }
            }
            self?.ticking = nil
        }
    }

    /// Whether there's more to show.
    private func tick(_ elapsed: Double) -> Bool {
        let count = reveal.step(through: target, elapsed: elapsed, finished: finished)
        let now = Date.timeIntervalSinceReferenceDate
        fresh.removeAll { now - $0.at > Self.fade }
        if count > 0 {
            shown = String(reveal.shown(of: target))
            fresh.append(Fresh(count: count, at: now))
        }
        return !reveal.caughtUp(with: target)
    }

    /// Still showing words, or fading the last in.
    var busy: Bool { ticking != nil || !fresh.isEmpty }
}
