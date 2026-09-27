import Foundation
import Testing

@testable import MoteCore

@Suite("TabSleep")
struct TabSleepTests {
    @Test("An idle page with nothing going on may sleep")
    func maySleep() {
        #expect(TabSleep.keepsAwake(TabSleep.Facts()) == nil)
    }

    @Test("Each thing going on keeps a tab awake")
    func keeps() {
        let cases: [(WritableKeyPath<TabSleep.Facts, Bool>, TabSleep.Reason)] = [
            (\.onScreen, .onScreen), (\.pinned, .pinned), (\.bench, .bench), (\.blank, .blank), (\.asleep, .asleep),
            (\.loading, .loading), (\.playingSound, .sound), (\.floating, .floating), (\.onCall, .call),
            (\.downloading, .downloading), (\.openedTheTabOnScreen, .opener),
        ]
        for (fact, reason) in cases {
            var tab = TabSleep.Facts()
            tab[keyPath: fact] = true
            #expect(TabSleep.keepsAwake(tab) == reason)
        }
        var pageless = TabSleep.Facts()
        pageless.hasPage = false
        #expect(TabSleep.keepsAwake(pageless) == .noPage)
    }

    @Test("Being on screen is reported before anything else")
    func order() {
        var tab = TabSleep.Facts()
        tab.onScreen = true
        tab.playingSound = true
        #expect(TabSleep.keepsAwake(tab) == .onScreen)
    }

    @Test("The limit is half an hour unless set, and checks run every quarter of it within bounds")
    func timing() {
        #expect(TabSleep.idleLimit(setting: 0) == 1800)
        #expect(TabSleep.idleLimit(setting: 12) == 12)
        #expect(TabSleep.checkEvery(limit: 1800) == 60)
        #expect(TabSleep.checkEvery(limit: 8) == 5)
        #expect(TabSleep.idleLimit(underPressure: false) == 300)
        #expect(TabSleep.idleLimit(underPressure: true) == 0)
    }

    @Test("Idle tabs come longest idle first")
    func idleOrder() {
        let now = Date()
        let tabs = [
            (id: "a", touched: now.addingTimeInterval(-100)), (id: "b", touched: now.addingTimeInterval(-500)), (id: "c", touched: now),
        ]
        #expect(TabSleep.idle(tabs, limit: 60, now: now) == ["b", "a"])
    }
}
