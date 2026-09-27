import AppKit
import MoteCore
import WebKit

// Tab sleep: tabs left idle let their page go and keep their history, scroll
// and a snapshot to come back from (see Tab.sleep). The rules are TabSleep's.
extension Browser {
    static var sleepAfter: TimeInterval { TabSleep.idleLimit(setting: Storage.settings.double(forKey: "sleep.after")) }

    /// Starts the idle check and listens for memory pressure. Once, at launch.
    func watchForSleep() {
        let every = TabSleep.checkEvery(limit: Browser.sleepAfter)
        let timer = Timer(timeInterval: every, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sleepIdle() }
        }
        timer.tolerance = every / 4
        RunLoop.main.add(timer, forMode: .common)
        dozing = timer

        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let event = self.pressure?.data else { return }
                self.sleepIdle(within: TabSleep.idleLimit(underPressure: event.contains(.critical)))
            }
        }
        source.resume()
        pressure = source
    }

    /// Puts every tab idle for `limit` to sleep, other spaces' included, longest idle first.
    func sleepIdle(within limit: TimeInterval = Browser.sleepAfter) {
        guard prefs.sleepsTabs else { return }
        let candidates = (tabs + parkedTabs).filter { awake(because: $0) == nil }
        let ids = TabSleep.idle(candidates.map { (id: $0.id, touched: $0.touched) }, limit: limit, now: Date())
        for tab in ids.compactMap({ id in candidates.first { $0.id == id } }) { sleep(tab) }
    }

    /// Why a tab has to stay awake, or nil. Idle time is the caller's to check.
    func awake(because tab: Tab) -> String? {
        var facts = TabSleep.Facts()
        facts.onScreen = tab.id == activeID
        facts.pinned = tab.pin != nil
        facts.bench = tab.bench
        facts.blank = tab.isBlank
        facts.asleep = tab.asleep
        facts.hasPage = tab.built != nil
        facts.loading = tab.loading
        facts.playingSound = tab.noisy
        facts.floating = tab.floating || floating == tab.id
        if let web = tab.built {
            facts.onCall = web.cameraCaptureState != .none || web.microphoneCaptureState != .none
            facts.downloading = downloading.contains { $0.webView === web }
        }
        facts.openedTheTabOnScreen = active?.opener == tab.id
        return TabSleep.keepsAwake(facts)?.rawValue
    }

    /// Checks for unsent input, takes a snapshot, then lets the page go. Each
    /// step waits on the page, so whether the tab may still sleep is asked
    /// again after each: the user may have come back to it.
    func sleep(_ tab: Tab, done: ((String) -> Void)? = nil) {
        if let reason = awake(because: tab) { return done?(reason) ?? () }
        tab.unsaved { [weak self, weak tab] typed in
            guard let self, let tab else { return }
            if typed { return done?(TabSleep.Reason.typed.rawValue) ?? () }
            if let reason = awake(because: tab) { return done?(reason) ?? () }
            tab.snapshot { [weak self, weak tab] picture in
                guard let self, let tab else { return }
                if let reason = awake(because: tab) { return done?(reason) ?? () }
                tab.sleep(picture: picture)
                done?("asleep")
            }
        }
    }
}
