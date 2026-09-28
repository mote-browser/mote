import AppKit
import SwiftUI
import WebKit

// Folding the tabs away (⌘S), and changes that give the page a new size.
extension Browser {
    /// Folds the sidebar or strip away, or back.
    func toggleFold() {
        peeking = false
        dissolvingPage { self.slidingFold { self.folded.toggle() } }
    }

    /// Shows or hides the folded tabs over the page.
    func peek(_ out: Bool) {
        slidingFold { peeking = out }
    }

    /// Well past the spring's end: a slide not finished by then is stuck.
    private static let foldLimit: Double = 0.8

    /// Changes the fold on the tabs' spring, making sure it gets drawn.
    /// SwiftUI has left the sidebar and card on the slide's first frame after
    /// a click on the sidebar button, while the traffic lights (moved by
    /// AppKit, see SidebarFold) went, until something else redrew the window.
    /// Asking the views again doesn't move it on, as nothing they draw has
    /// changed; a real change without animation does, so a slide that hasn't
    /// finished well after it should have gets one (see `foldNudge`).
    func slidingFold(_ change: () -> Void) {
        foldSlides += 1
        let slide = foldSlides
        withAnimation(Motion.fold, completionCriteria: .logicallyComplete, change) { [weak self] in
            guard let self else { return }
            foldLanded = max(foldLanded, slide)
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.foldLimit))
            // Only the latest slide: a newer one takes over from it.
            guard let self, foldSlides == slide, foldLanded < slide else { return }
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { foldNudge.toggle() }
        }
    }

    /// Makes a change that resizes the page under a picture of it, which then
    /// fades into the new layout (see `PageCard`). Pages reflow in jumps and
    /// WebKit draws a frame behind every resize, so resizing on each frame of
    /// a slide judders; this way the page takes its new size once, out of
    /// sight. Taking the picture needs a frame or two; after a short wait the
    /// change goes ahead without one.
    func dissolvingPage(_ change: @escaping () -> Void) {
        guard let tab = active, !tab.isBlank, !tab.floating, let web = tab.built, web.window != nil else { return change() }
        var done = false
        let go = { [weak self] (picture: NSImage?) in
            guard let self, !done else { return }
            done = true
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { pageVeil = picture }
            change()
            if picture != nil {
                Task { @MainActor in withAnimation(.easeOut(duration: 0.34)) { self.pageVeil = nil } }
            }
        }
        web.takeSnapshot(with: nil) { picture, _ in MainActor.assumeIsolated { go(picture) } }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.1))
            go(nil)
        }
    }
}
