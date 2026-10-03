import AppKit
import SwiftUI
import WebKit

// Folding the tabs away (⌘S), and changes that give the page a new size.
extension Browser {
    /// Folds the sidebar or strip away, or back.
    func toggleFold() {
        peeking = false
        // AppKit animates the sidebar. Commit its target immediately so rapid
        // clicks cannot queue changes behind asynchronous WebKit snapshots.
        if prefs.sidebar { folded.toggle() } else { slidingFold { folded.toggle() } }
    }

    /// Shows or hides the folded tabs over the page.
    func peek(_ out: Bool) {
        slidingFold { peeking = out }
    }

    /// Overlay peeks, the top tab strip and page chat use SwiftUI; the docked
    /// sidebar's frame belongs exclusively to NSSplitViewController.
    func slidingFold(_ change: () -> Void) {
        withAnimation(Motion.fold, change)
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
