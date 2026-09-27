/// Which window command a key press means.
public enum KeyMap {
    /// A key as pressed.
    public struct Press: Equatable, Sendable {
        /// The character without modifiers, lowercased.
        public var key: String
        public var code: UInt16
        public var command = false
        public var shift = false
        public var option = false
        public var control = false

        public init(key: String, code: UInt16, command: Bool = false, shift: Bool = false, option: Bool = false, control: Bool = false) {
            self.key = key.lowercased()
            self.code = code
            self.command = command
            self.shift = shift
            self.option = option
            self.control = control
        }
    }

    public enum Command: Equatable, Sendable {
        case newTab, newPrivateTab, reopenTab, closeTab, duplicateTab
        case nextTab, previousTab
        /// A tab by position; `last` for ⌘9.
        case tab(Int), lastTab
        case space(Int)
        case back, forward, reload, reader
        case editAddress, switcher, pasteAndGo, copyAddress
        case find, findAgain(backwards: Bool)
        case print, pauseSound, floatVideo
        case toggleSidebar, foldTabs
        case bookmark, history, downloads, settings
        case hideElements, hiddenElements, undoHiding
        case zoomIn, zoomOut, actualSize
    }

    public static let escape: UInt16 = 53
    public static let tabKey: UInt16 = 48
    public static let leftArrow: UInt16 = 123
    public static let rightArrow: UInt16 = 124

    /// The top row's digits by key code, so shortcuts don't depend on the
    /// layout (AZERTY types other characters there).
    public static let digits: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9, 29: 0]

    /// What `press` means. `spaces`: spaces are on (⌃1–⌃9 switch them).
    /// `picking`: elements are being picked (⌘Z undoes a hide). `inText`:
    /// the keyboard is in something editable (⌘← and ⌘→ belong to it).
    public static func command(for press: Press, spaces: Bool, picking: Bool, inText: Bool) -> Command? {
        // ⌃⇥ and ⌃⇧⇥ step through the tabs.
        if press.code == tabKey, press.control, !press.command, !press.option { return press.shift ? .previousTab : .nextTab }
        if spaces, press.control, !press.command, !press.option, !press.shift, let number = digits[press.code], number > 0 {
            return .space(number - 1)
        }
        guard press.command, !press.option, !press.control else { return nil }
        if !press.shift, let number = digits[press.code] {
            return number == 0 ? .actualSize : number == 9 ? .lastTab : .tab(number - 1)
        }
        switch (press.key, press.shift) {
        case ("t", false): return .newTab
        case ("t", true): return .reopenTab
        case ("n", true): return .newPrivateTab
        case ("w", false): return .closeTab
        case ("d", false): return .duplicateTab
        case ("c", true): return .copyAddress
        case ("v", true): return .pasteAndGo
        case ("l", false): return .editAddress
        case ("k", false): return .switcher
        case ("r", false): return .reload
        case ("r", true): return .reader
        case ("y", false): return .history
        case ("j", true): return .downloads
        case ("p", false): return .print
        case ("p", true): return .floatVideo
        case ("f", false): return .find
        case ("g", let shift): return .findAgain(backwards: shift)
        case ("m", true): return .pauseSound
        case ("s", true): return .toggleSidebar
        case ("s", false): return .foldTabs
        case ("b", true): return .bookmark
        case (",", false): return .settings
        case ("h", true): return .hideElements
        case ("u", true): return .hiddenElements
        case ("z", false): return picking ? .undoHiding : nil
        // ⌘+ comes as "=" or "+" depending on the layout.
        case ("=", _), ("+", _): return .zoomIn
        case ("-", _): return .zoomOut
        case ("0", _): return .actualSize
        case ("[", let shift): return shift ? .previousTab : .back
        case ("]", let shift): return shift ? .nextTab : .forward
        case ("{", true): return .previousTab
        case ("}", true): return .nextTab
        default:
            guard !press.shift, !inText else { return nil }
            return press.code == leftArrow ? .back : press.code == rightArrow ? .forward : nil
        }
    }

    /// Shortcuts the page gets to see first, as in Chrome: if it doesn't use
    /// one, WebKit sends it back and Mote takes it then. Opening, closing and
    /// switching tabs are always Mote's, and so is ⌘Z while picking.
    public static func pageGoesFirst(_ press: Press, picking: Bool) -> Bool {
        let tabs = ["[", "]", "{", "}"]
        switch (press.key, press.shift) {
        case ("t", _), ("w", false), ("n", true): return false
        case (let key, true) where tabs.contains(key): return false
        case ("z", _) where picking: return false
        default: return true
        }
    }

    /// What a key does in the small window for links from other apps: ⌘O
    /// keeps the page as a tab, Escape and ⌘W close the window, and the rest
    /// go to the page.
    public enum LinkWindowKey: Equatable, Sendable { case keep, close }

    public static func linkWindow(_ press: Press) -> LinkWindowKey? {
        let plain = !press.command && !press.shift && !press.option && !press.control
        let commandOnly = press.command && !press.shift && !press.option && !press.control
        if press.code == escape, plain { return .close }
        guard commandOnly else { return nil }
        switch press.key {
        case "w": return .close
        case "o": return .keep
        default: return nil
        }
    }
}
