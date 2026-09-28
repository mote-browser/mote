import AppKit
import MoteAI
import MoteCore
import SwiftUI

/// The window's keyboard shortcuts. The page's web view takes most keys as
/// first responder, so a local monitor sees them first. Which command a key
/// means is KeyMap's; this carries it out.
@MainActor
final class KeyRouter {
    private weak var browser: Browser?
    private var monitor: Any?
    /// The last key left to the page first (see KeyMap.pageGoesFirst).
    private var leftToPage: NSEvent?

    func start(for browser: Browser) {
        self.browser = browser
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard event.type == .keyDown else {
                // Letting go of ⌘ goes to the tab picked with ⌘K.
                if !event.modifierFlags.contains(.command) { self?.browser?.landSummon() }
                return event
            }
            // nil means the key was used; only a router that's gone lets it through.
            guard let self else { return event }
            return self.route(event)
        }
    }

    /// nil when the key was used.
    func route(_ event: NSEvent) -> NSEvent? {
        take(event) ? nil : event
    }

    private func take(_ event: NSEvent) -> Bool {
        // The small link window and Settings have keys of their own.
        if let little = LinkWindow.owning(event.window) { return little.take(event) }
        if let settings = SettingsWindow.owning(event.window) { return settings.take(event) }
        guard let browser else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let press = KeyMap.Press(
            key: event.charactersIgnoringModifiers ?? "", code: event.keyCode, command: flags.contains(.command),
            shift: flags.contains(.shift),
            option: flags.contains(.option), control: flags.contains(.control))

        if press.code == KeyMap.escape { return escape(in: browser) }
        // AppKit's field editor has no command for ⌘Return, so it's caught here.
        let inField = AddressField.hasKeyboard(in: event.window) && !browser.field.switching
        if KeyMap.asks(press, inAddressField: inField) {
            browser.ask()
            return true
        }
        // Tab (without ⌘, ⌥ or ⌃) walks the suggestions while the field is open,
        // is swallowed while renaming a tab, and otherwise goes to the page.
        if press.code == KeyMap.tabKey, !press.command, !press.option, !press.control {
            if browser.editingTab != nil { return true }
            guard browser.fieldShowing, !browser.field.offers.isEmpty else { return false }
            browser.field.walk(press.shift ? -1 : 1)
            return true
        }
        let inText = browser.active?.typing == true || event.window?.firstResponder is NSTextView
        let command = KeyMap.command(for: press, spaces: browser.prefs.usesSpaces, picking: browser.pickingElement, inText: inText)
        // ⌃ shortcuts of Mote's own (spaces, ⌃⇥) come before extensions'.
        if let command, !press.command {
            run(command, in: browser, event: event)
            return true
        }
        // Extensions get the rest of the shortcuts first.
        if #available(macOS 15.4, *), press.command || press.option || press.control, Extensions.shared.take(event) { return true }
        guard let command else { return false }
        if !isDigit(press), leavesToPage(event, press, picking: browser.pickingElement) { return false }
        run(command, in: browser, event: event)
        return true
    }

    private func isDigit(_ press: KeyMap.Press) -> Bool { !press.shift && KeyMap.digits[press.code] != nil }

    /// Lets the page have a shortcut first, as Chrome does, when the page has
    /// the keyboard. If it doesn't use it, WebKit sends the same key again,
    /// and this time Mote takes it.
    private func leavesToPage(_ event: NSEvent, _ press: KeyMap.Press, picking: Bool) -> Bool {
        guard KeyMap.pageGoesFirst(press, picking: picking), event.window?.firstResponder is PageView else { return false }
        if let earlier = leftToPage, PageView.same(earlier, event) {
            leftToPage = nil
            return false
        }
        leftToPage = event
        return true
    }

    /// Escape closes whatever is on top, one thing at a time.
    private func escape(in browser: Browser) -> Bool {
        let steps: [(Bool, () -> Void)] = [
            (browser.welcoming, browser.finishWelcome),
            (browser.editingTab != nil, browser.cancelTabEdit),
            (browser.peekTab != nil, browser.closePeek),
            (browser.makingSpace, { withAnimation(Motion.glide) { browser.makingSpace = false } }),
            (browser.bookmarking, { browser.bookmarking = false }),
            (browser.logins.managing, { browser.logins.managing = false }),
            (browser.recalling, { browser.recalling = false }),
            (browser.showingDownloads, { browser.showingDownloads = false }),
            (browser.logins.choices != nil, browser.logins.dropChoices),
            (browser.pickingElement, browser.toggleHiding),
            (browser.reviewing, { browser.reviewing = false }),
            (browser.finder.showing, browser.finder.hide),
            // The pick goes before the field does.
            (browser.field.picked != nil, { browser.field.picked = nil }),
            (browser.editing && browser.active?.isStart == false, browser.dismiss),
            // Last, so Escape first closes whatever is over the chat.
            (browser.active?.chat?.busy == true, { browser.active?.chat?.stop() }),
        ]
        guard let step = steps.first(where: \.0) else { return false }
        step.1()
        return true
    }

    private func run(_ command: KeyMap.Command, in browser: Browser, event: NSEvent) {
        switch command {
        case .newTab: browser.newTab()
        case .newPrivateTab: browser.newShyTab()
        case .reopenTab: browser.reopen()
        case .closeTab:
            if browser.peekTab != nil { browser.closePeek() } else if let tab = browser.active { browser.close(tab) }
        case .duplicateTab: browser.duplicate()
        case .nextTab: browser.step(1)
        case .previousTab: browser.step(-1)
        case .tab(let index): browser.select(index: index)
        case .lastTab: browser.select(index: browser.tabs.count - 1)
        case .space(let index): browser.switchSpace(index: index)
        case .back: browser.back()
        case .forward: browser.forward()
        case .reload: browser.reload()
        case .reader: browser.toggleReader()
        case .editAddress: browser.edit()
        case .switcher:
            // ⌘K again moves the pick; letting go of ⌘ goes there.
            if browser.editing, !browser.field.offers.isEmpty { browser.stepSummon() } else { browser.summon() }
        case .pasteAndGo: pasteAndGo(in: browser, event: event)
        case .copyAddress: browser.copyAddress()
        case .find: browser.openFind()
        case .findAgain(let backwards): browser.finder.look(forward: !backwards)
        case .print: browser.printPage()
        case .pauseSound: browser.pauseMedia()
        case .floatVideo: browser.toggleFloat()
        case .toggleSidebar: browser.toggleSidebar()
        case .foldTabs: browser.toggleFold()
        case .bookmark: browser.bookmarkCurrent()
        case .history: browser.recalling.toggle()
        case .downloads: browser.showingDownloads.toggle()
        // Opens Settings, or brings it forward.
        case .settings: browser.tuning = true
        case .hideElements: browser.toggleHiding()
        case .hiddenElements: browser.reviewing.toggle()
        case .undoHiding: browser.undoHiding()
        case .zoomIn: browser.zoom(by: 1.1)
        case .zoomOut: browser.zoom(by: 1 / 1.1)
        case .actualSize: browser.resetZoom()
        }
    }

    /// ⇧⌘V: pastes plain text in anything editable, otherwise Paste and Go.
    /// WebKit gives ⇧⌘V back unused, so the plain paste is done here.
    /// `inputContext` is set whenever the caret is in something editable, in
    /// any frame, other sites' included.
    private func pasteAndGo(in browser: Browser, event: NSEvent) {
        let editable =
            browser.active?.typing == true || browser.active?.built?.inputContext != nil || browser.editing
            || event.window?.firstResponder is NSTextView
        if editable {
            _ = event.window?.firstResponder?.tryToPerform(#selector(NSTextView.pasteAsPlainText(_:)), with: nil)
        } else {
            browser.pasteAndGo()
        }
    }
}
