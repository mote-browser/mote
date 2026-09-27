import Foundation
import Testing

@testable import Mote

@Suite("Announcements")
@MainActor
struct AnnouncementTests {
    @Test("A plain line goes quickly; one with more to say or do stays")
    func lasting() {
        #expect(Announcement("Bookmarked").lasts == 2)
        #expect(Announcement("Saved", detail: "In your keychain").lasts == 4)
        #expect(Announcement("Mote 0.2.0 is here", action: .init(title: "Open Settings") {}).lasts == 8)
        #expect(Announcement("Same") != Announcement("Same"))
    }

    @Test("An update's notice opens Settings on About, even when it's open on another page")
    func opensAbout() async throws {
        let browser = Browser()
        let key = "settings.page"
        let before = Storage.settings.string(forKey: key)
        defer { Storage.settings.set(before, forKey: key) }

        browser.openSettings(at: .about)
        #expect(Storage.settings.string(forKey: key) == "about")
        #expect(browser.tuning)

        Storage.settings.set("tabs", forKey: key)
        browser.openSettings(at: .about)
        #expect(Storage.settings.string(forKey: key) == "about")
        #expect(!browser.tuning)
        try await Task.sleep(for: .milliseconds(50))
        #expect(browser.tuning)
        browser.tuning = false
    }

    @Test("Resting on a message keeps it; dismissing it clears it")
    func holding() async throws {
        let browser = Browser()
        browser.announce("Bookmarked")
        browser.holdAnnouncement(true)
        try await Task.sleep(for: .seconds(2.3))
        #expect(browser.announcement?.text == "Bookmarked")
        browser.dismissAnnouncement()
        #expect(browser.announcement == nil)
    }
}
