import AppKit
import XCTest

/// End-to-end tests: the real app, driven through its interface, in its own
/// test world so they never touch anyone's data.
final class MoteUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(sidebar: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["MOTE_PROBE"] = "ui-tests"
        // Property-list values, so settings read as booleans see booleans rather than strings.
        app.launchArguments += ["-welcomed", "YES", "-sidebar", sidebar ? "<true/>" : "<false/>", "-sidebar.hides", "<false/>"]
        app.launch()
        return app
    }

    @MainActor
    func testLaunchShowsTheBrowserWindow() {
        let app = launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }

    /// Pastes the address rather than typing it: synthesized typing drops
    /// characters such as ":" on some keyboard layouts.
    @MainActor
    func testPastingAnAddressOpensThePage() {
        let app = launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("data:text/html,<title>MoteUITest</title><p>Hello-from-Mote</p>", forType: .string)
        app.typeKey("t", modifierFlags: .command)
        app.typeKey("v", modifierFlags: .command)
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(app.webViews.staticTexts["Hello-from-Mote"].waitForExistence(timeout: 10))
    }

    /// Opens the bookmarks menu from its button and waits for it.
    @MainActor
    private func openBookmarksMenu(in app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        let button = app.buttons["Bookmarks"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.click()
        let item = app.staticTexts["Add This Page"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        return item
    }

    @MainActor
    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    @MainActor
    func testClickingElsewhereClosesTheBookmarksMenu() {
        let app = launch()
        let item = openBookmarksMenu(in: app)

        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).click()

        XCTAssertTrue(waitUntilGone(item), "The bookmarks menu is still open after a click elsewhere")
    }

    @MainActor
    func testSwitchingAppsClosesTheBookmarksMenu() {
        let app = launch()
        let item = openBookmarksMenu(in: app)

        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()

        XCTAssertTrue(waitUntilGone(item), "The bookmarks menu stays on screen over another app")
        app.activate()
    }

    @MainActor
    func testTheBookmarksMenuOpensAndClosesAgainAndAgain() {
        let app = launch()
        for _ in 0..<3 {
            let item = openBookmarksMenu(in: app)
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).click()
            XCTAssertTrue(waitUntilGone(item), "A click elsewhere left the bookmarks menu open")
        }
        let item = openBookmarksMenu(in: app)
        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()
        XCTAssertTrue(waitUntilGone(item), "The bookmarks menu stays on screen over another app")
        app.activate()
    }

    // MARK: - Chrome

    /// Opens a page by pasting its address into a new tab.
    @MainActor
    private func openPage(_ text: String, in app: XCUIApplication) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("data:text/html,<title>MoteUITest</title><p>\(text)</p>", forType: .string)
        app.typeKey("t", modifierFlags: .command)
        app.typeKey("v", modifierFlags: .command)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.webViews.staticTexts[text].waitForExistence(timeout: 10))
    }

    @MainActor
    func testTheToolbarCarriesTheNavigationButtons() {
        let app = launch(sidebar: true)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        for name in ["Back", "Forward", "Reload", "Hide Sidebar", "Bookmarks"] {
            XCTAssertTrue(app.buttons[name].firstMatch.waitForExistence(timeout: 5), "No \(name) button in the toolbar")
        }
    }

    @MainActor
    func testBackAndForwardFromTheToolbar() {
        let app = launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        openPage("First-page", in: app)
        app.typeKey("l", modifierFlags: .command)
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("data:text/html,<p>Second-page</p>", forType: .string)
        app.typeKey("v", modifierFlags: .command)
        let pasted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS 'Second-page'"), object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [pasted], timeout: 3), .completed, "The address didn't go into the field")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.webViews.staticTexts["Second-page"].waitForExistence(timeout: 10))

        app.buttons["Back"].firstMatch.click()
        XCTAssertTrue(app.webViews.staticTexts["First-page"].waitForExistence(timeout: 10))
        app.buttons["Forward"].firstMatch.click()
        XCTAssertTrue(app.webViews.staticTexts["Second-page"].waitForExistence(timeout: 10))
    }

    /// The sidebar button folds the sidebar away; the pointer at the window's
    /// left edge brings it out over the page, and moving away puts it back.
    @MainActor
    func testTheFoldedSidebarPeeksFromTheLeftEdge() {
        let app = launch(sidebar: true)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let newTab = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'New tab'")).firstMatch
        XCTAssertTrue(newTab.waitForExistence(timeout: 5), "The sidebar isn't showing")

        app.buttons["Hide Sidebar"].firstMatch.click()
        XCTAssertTrue(waitUntilGone(newTab), "The sidebar is still showing after folding it")
        XCTAssertTrue(app.buttons["Show Sidebar"].firstMatch.waitForExistence(timeout: 5))

        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
        window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 2, dy: 0)).hover()
        XCTAssertTrue(newTab.waitForExistence(timeout: 5), "The sidebar didn't come out at the left edge")

        window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).hover()
        XCTAssertTrue(waitUntilGone(newTab), "The sidebar stayed out after the pointer left it")

        app.buttons["Show Sidebar"].firstMatch.click()
        XCTAssertTrue(newTab.waitForExistence(timeout: 5), "The sidebar didn't come back")
    }

    /// ⌘L on a page edits the address in the toolbar, with the address selected;
    /// Escape puts the site back.
    @MainActor
    func testCommandLEditsTheAddressInTheToolbar() {
        let app = launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        openPage("Address-page", in: app)
        XCTAssertEqual(app.textFields.count, 0, "An address field is open over the page")

        app.typeKey("l", modifierFlags: .command)
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue((field.value as? String)?.hasPrefix("data:text/html") == true)

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntilGone(field), "The address field stayed open after Escape")
    }

    @MainActor
    func testANewTabShowsTheComposer() {
        let app = launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))
        let go = app.buttons["Go"].firstMatch
        XCTAssertTrue(go.waitForExistence(timeout: 5))
        XCTAssertFalse(go.isEnabled, "Go is enabled with nothing typed")
        app.typeKey("m", modifierFlags: [])
        XCTAssertTrue(go.isEnabled, "Go stays disabled with something typed")
    }

    @MainActor
    func testInitialAssistantComposerCanStageAndRemoveLocalMention() throws {
        let app = launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))

        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("MoteMention-\(UUID().uuidString).html")
        try "<html><head><title>LocalMentionFixture</title></head><body>Local mention page</body></html>".write(
            to: fixture, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fixture) }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fixture.absoluteURL.absoluteString, forType: .string)
        app.typeKey("v", modifierFlags: .command)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.webViews.staticTexts["Local mention page"].waitForExistence(timeout: 10))

        app.typeKey("t", modifierFlags: .command)
        app.typeKey("j", modifierFlags: .command)
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.typeText("@")

        let candidate = app.buttons["Mention LocalMentionFixture"].firstMatch
        XCTAssertTrue(candidate.waitForExistence(timeout: 5), "The initial AI composer has no @ picker")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.exists, "Escape closed the initial composer instead of only dismissing its picker")
        XCTAssertTrue(waitUntilGone(candidate), "Escape left the mention picker open")

        app.typeKey(.delete, modifierFlags: [])
        app.typeText("@")
        XCTAssertTrue(candidate.waitForExistence(timeout: 5))
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.tab, modifierFlags: [])
        let remove = app.buttons["Stop mentioning LocalMentionFixture"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "Tab did not stage the highlighted page")
        remove.click()
        XCTAssertTrue(waitUntilGone(remove), "The staged page chip did not remove its context")

        app.typeText("@")
        XCTAssertTrue(candidate.waitForExistence(timeout: 5))
        app.typeKey("j", modifierFlags: .command)
        XCTAssertTrue(waitUntilGone(candidate), "Switching back to search left the AI mention popup open")
        app.typeKey("j", modifierFlags: .command)
        XCTAssertFalse(app.buttons["Stop mentioning LocalMentionFixture"].exists, "Mode switching retained a stale staged page")
    }

    @MainActor
    func testPretypedMentionRefreshesOnAssistantModeSwitchAndCanReachSeventhResult() throws {
        let app = launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))

        var fixtures: [URL] = []
        defer { fixtures.forEach { try? FileManager.default.removeItem(at: $0) } }
        for index in 1...7 {
            let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("MoteMention-\(UUID().uuidString).html")
            try "<html><head><title>LocalMentionFixture\(index)</title></head><body>Local mention page \(index)</body></html>".write(
                to: fixture, atomically: true, encoding: .utf8)
            fixtures.append(fixture)

            if index > 1 { app.typeKey("t", modifierFlags: .command) }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(fixture.absoluteURL.absoluteString, forType: .string)
            app.typeKey("l", modifierFlags: .command)
            app.typeKey("v", modifierFlags: .command)
            app.typeKey(.return, modifierFlags: [])
            XCTAssertTrue(app.webViews.staticTexts["Local mention page \(index)"].waitForExistence(timeout: 10))
        }

        app.typeKey("t", modifierFlags: .command)
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.typeText("@")
        app.typeKey("j", modifierFlags: .command)

        let seventh = app.buttons["Mention LocalMentionFixture7"].firstMatch
        XCTAssertTrue(seventh.waitForExistence(timeout: 5), "Changing to AI mode did not refresh the pretyped @ query")
        for _ in 0..<7 { app.typeKey(.downArrow, modifierFlags: []) }
        XCTAssertTrue(seventh.isHittable, "Keyboard highlight moved past the visible rows without scrolling the selected result into view")

        app.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(
            app.buttons["Stop mentioning LocalMentionFixture7"].waitForExistence(timeout: 5),
            "The shared picker could not confirm its seventh result"
        )
    }
}
