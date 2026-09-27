import AppKit
import MoteCore

// The floating video window: a tab's video playing on top of other apps.
extension Browser {
    /// ⌘⇧P.
    func toggleFloat() {
        if floater.showing { land() } else { lift(active, quietly: false) }
    }

    /// Before another tab takes over: floats this tab's video when that is on.
    func floatActiveVideo() {
        if prefs.floatsOnLeave { lift(active, quietly: true) }
    }

    /// The app went to the background: float the video when that is on.
    func appLeft() {
        guard prefs.floatsAway, Browser.front == nil || Browser.front === self else { return }
        floatedAway = !floater.showing
        lift(active, quietly: true)
    }

    /// Back in the app: a video floated on the way out returns to its tab if
    /// that tab is still showing.
    func appBack() {
        defer { floatedAway = false }
        if floatedAway, let id = floating, id == activeID { land() }
    }

    /// Moves the tab's page into the floating window with the video alone on it.
    /// Quiet floats (not asked for with ⌘⇧P) only happen on known video sites.
    private func lift(_ tab: Tab?, quietly: Bool) {
        // A waiting tab has no page; asking would build an empty one.
        guard let tab, !tab.isBlank, !tab.asleep, !floater.showing else { return }
        if quietly, !VideoSites.contains(tab.address) { return }
        tab.web.isolate(.on) { [weak self] answer in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard (answer as? String) == "floating" else {
                    if !quietly { self.announce("Nothing is playing here") }
                    return
                }
                self.floating = tab.id
                tab.floating = true
                self.floater.lift(tab.web)
            }
        }
    }

    /// Returns the video to its tab; the stage takes the page back on its
    /// next layout.
    func land() {
        // Close the window whatever happened to the tab.
        if floater.showing { floater.drop() }
        guard let tab = floating.flatMap(tab) else { return }
        floating = nil
        tab.floating = false
        tab.web.isolate(.off)
    }

    /// Connects the floating window's buttons to the floating tab.
    func wireFloater() {
        floater.onReturn = { [weak self] in
            guard let self else { return }
            let came = floating
            land()
            if let tab = came.flatMap(tab) { select(tab) }
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.contentView != nil }?.makeKeyAndOrderFront(nil)
        }
        floater.onClose = { [weak self] in self?.land() }
        floater.onSkip = { [weak self] seconds in self?.floatingTab?.web.isolate(.skip, seconds: seconds) }
        floater.onProgress = { [weak self] answer in
            self?.floatingTab?.web.isolate(.progress) { found in
                MainActor.assumeIsolated {
                    guard let pair = found as? [Any], pair.count == 2, let through = pair[0] as? Double,
                        let playing = pair[1] as? Bool
                    else { return }
                    answer(through, playing)
                }
            }
        }
        floater.onPlayPause = { [weak self] answer in
            self?.floatingTab?.web.isolate(.toggle) { playing in
                MainActor.assumeIsolated { answer((playing as? Bool) ?? true) }
            }
        }
    }

    private var floatingTab: Tab? { floating.flatMap(tab) }
}
