import Testing

@testable import MoteCore

@Suite("KeyMap")
struct KeyMapTests {
    private func command(
        _ key: String, _ code: UInt16 = 0, command: Bool = true, shift: Bool = false, option: Bool = false, control: Bool = false,
        spaces: Bool = false, picking: Bool = false, inText: Bool = false
    ) -> KeyMap.Command? {
        KeyMap.command(
            for: KeyMap.Press(key: key, code: code, command: command, shift: shift, option: option, control: control), spaces: spaces,
            picking: picking, inText: inText)
    }

    @Test("⌘J switches asking the assistant on and off, only in a new tab's composer, whatever the layout")
    func asking() {
        let press = { (key: String, shift: Bool, option: Bool) in
            KeyMap.Press(key: key, code: KeyMap.jKey, command: true, shift: shift, option: option)
        }
        #expect(KeyMap.switchesAsking(press("j", false, false), inComposer: true))
        // Another layout types something else on that key.
        #expect(KeyMap.switchesAsking(press("ж", false, false), inComposer: true))
        #expect(!KeyMap.switchesAsking(press("j", false, false), inComposer: false))
        #expect(!KeyMap.switchesAsking(press("J", true, false), inComposer: true))
        #expect(!KeyMap.switchesAsking(press("j", false, true), inComposer: true))
        #expect(!KeyMap.switchesAsking(KeyMap.Press(key: "j", code: KeyMap.jKey), inComposer: true))
    }

    @Test("Everyday shortcuts")
    func everyday() {
        #expect(command("t") == .newTab)
        #expect(command("T", shift: true) == .reopenTab)
        #expect(command("w") == .closeTab)
        #expect(command("l") == .editAddress)
        #expect(command("k") == .switcher)
        #expect(command("g", shift: true) == .findAgain(backwards: true))
        #expect(command(",") == .settings)
    }

    @Test("Digits go by key code, so ⌘1 works on AZERTY too, and ⌘9 is the last tab")
    func digits() {
        #expect(command("&", 18) == .tab(0))
        #expect(command("(", 25) == .lastTab)
        #expect(command("à", 29) == .actualSize)
    }

    @Test("⌃1–⌃9 are spaces only when spaces are on")
    func spaces() {
        #expect(command("1", 18, command: false, control: true, spaces: true) == .space(0))
        #expect(command("1", 18, command: false, control: true) == nil)
    }

    @Test("⌃⇥ steps through tabs; brackets go back, forward, or between tabs with shift")
    func stepping() {
        #expect(command("\t", KeyMap.tabKey, command: false, control: true) == .nextTab)
        #expect(command("\t", KeyMap.tabKey, command: false, shift: true, control: true) == .previousTab)
        #expect(command("[") == .back)
        #expect(command("{", shift: true) == .previousTab)
    }

    @Test("Zoom keys, whatever the layout sends")
    func zoom() {
        #expect(command("=") == .zoomIn)
        #expect(command("+", shift: true) == .zoomIn)
        #expect(command("-") == .zoomOut)
    }

    @Test("⌘Z only undoes a hide while picking")
    func undo() {
        #expect(command("z") == nil)
        #expect(command("z", picking: true) == .undoHiding)
    }

    @Test("⌘← and ⌘→ navigate, unless typing")
    func arrows() {
        #expect(command("", KeyMap.leftArrow) == .back)
        #expect(command("", KeyMap.rightArrow, inText: true) == nil)
    }

    @Test("Option or Control with ⌘ are left alone, and nothing happens without ⌘")
    func others() {
        #expect(command("t", option: true) == nil)
        #expect(command("t", command: false) == nil)
    }

    @Test("Tabs stay Mote's; most other shortcuts go to the page first")
    func pageFirst() {
        func first(_ key: String, shift: Bool = false, picking: Bool = false) -> Bool {
            KeyMap.pageGoesFirst(KeyMap.Press(key: key, code: 0, command: true, shift: shift), picking: picking)
        }
        #expect(!first("t"))
        #expect(!first("w"))
        #expect(first("w", shift: true))
        #expect(!first("n", shift: true))
        #expect(!first("]", shift: true))
        #expect(first("]"))
        #expect(first("z"))
        #expect(!first("z", picking: true))
        #expect(first("l"))
    }

    @Test("The link window keeps with ⌘O and closes with ⌘W or Escape; the rest is the page's")
    func linkWindow() {
        #expect(KeyMap.linkWindow(KeyMap.Press(key: "O", code: 31, command: true)) == .keep)
        #expect(KeyMap.linkWindow(KeyMap.Press(key: "w", code: 13, command: true)) == .close)
        #expect(KeyMap.linkWindow(KeyMap.Press(key: "\u{1b}", code: KeyMap.escape)) == .close)
        #expect(KeyMap.linkWindow(KeyMap.Press(key: "\u{1b}", code: KeyMap.escape, shift: true)) == nil)
        #expect(KeyMap.linkWindow(KeyMap.Press(key: "w", code: 13, command: true, shift: true)) == nil)
        #expect(KeyMap.linkWindow(KeyMap.Press(key: "o", code: 31)) == nil)
        #expect(KeyMap.linkWindow(KeyMap.Press(key: "t", code: 17, command: true)) == nil)
    }
}
