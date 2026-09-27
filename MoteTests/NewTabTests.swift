import AppKit
import Testing

@testable import Mote

@Suite("New tabs", .serialized)
@MainActor
struct NewTabTests {
    @Test("⌘T opens a new tab every time, even beside another blank one")
    func alwaysNew() {
        let browser = Browser()
        defer { for tab in browser.tabs { tab.close() } }
        browser.newTab()
        let first = browser.activeID
        let before = browser.tabs.count
        browser.newTab()
        #expect(browser.tabs.count == before + 1)
        #expect(browser.activeID != first)
        #expect(browser.tabs.last?.id == browser.activeID)
        #expect(browser.active?.isBlank == true)
    }

    @Test("A new private tab is new every time too")
    func privateAlwaysNew() {
        let browser = Browser()
        defer { for tab in browser.tabs { tab.close() } }
        browser.newShyTab()
        let first = browser.activeID
        let before = browser.tabs.count
        browser.newShyTab()
        #expect(browser.tabs.count == before + 1)
        #expect(browser.activeID != first)
        #expect(browser.active?.shy == true)
    }
}
