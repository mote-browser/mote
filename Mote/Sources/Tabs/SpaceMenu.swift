import AppKit
import MoteCore

/// The spaces menu: every space, then what can be done to this one.
@MainActor
enum SpaceMenu {
    private static func item(
        _ title: String, key: String = "", checked: Bool = false, symbol: String? = nil, _ run: @escaping () -> Void
    ) -> NSMenuItem {
        let item = ActionItem(title, key: key, run)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : .control
        item.state = checked ? .on : .off
        item.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: title) }
        return item
    }

    static func show(for browser: Browser) {
        let menu = NSMenu()
        for (index, space) in browser.spaces.enumerated() {
            menu.addItem(
                item(space.name, key: index < 9 ? "\(index + 1)" : "", checked: space.id == browser.spaceID, symbol: space.symbol) {
                    browser.switchSpace(to: space.id)
                })
        }
        menu.addItem(.separator())
        menu.addItem(item("New Space…") { browser.askForSpace() })
        menu.addItem(.separator())
        for entry in actions(on: browser.space, in: browser) { menu.addItem(entry) }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private static func actions(on here: Space, in browser: Browser) -> [NSMenuItem] {
        var items = [
            item("Rename “\(here.name)”…") {
                Prompt.name("Rename Space", placeholder: here.name, initial: here.name, confirm: "Rename") {
                    browser.renameSpace(here.id, to: $0)
                }
            }
        ]
        let icons = NSMenu()
        for (symbol, name) in Space.icons {
            icons.addItem(item(name, checked: here.symbol == symbol, symbol: symbol) { browser.setSpaceIcon(here.id, to: symbol) })
        }
        let icon = NSMenuItem(title: "Icon", action: nil, keyEquivalent: "")
        icon.submenu = icons
        items.append(icon)
        // The order is the swipe order and ⌃1–⌃9's.
        if let at = browser.spaces.firstIndex(where: { $0.id == here.id }) {
            if at > 0 { items.append(item("Move Left") { browser.moveSpace(here.id, to: at - 1) }) }
            if at < browser.spaces.count - 1 { items.append(item("Move Right") { browser.moveSpace(here.id, to: at + 1) }) }
        }
        let folder = here.downloads.map { URL(fileURLWithPath: $0).lastPathComponent }
        items.append(
            item(folder.map { "Downloads to “\($0)”…" } ?? "Downloads Folder…") {
                Prompt.folder { browser.setSpaceDownloads(here.id, to: $0) }
            })
        if folder != nil { items.append(item("Use the Downloads Folder in Settings") { browser.setSpaceDownloads(here.id, to: nil) }) }
        if !here.isFirst {
            items.append(.separator())
            items.append(
                item("Delete “\(here.name)”…") {
                    Prompt.confirm(
                        "Delete “\(here.name)”?",
                        detail: "Its tabs close and its cookies and sign-ins are removed from this Mac. History and bookmarks are kept.",
                        confirm: "Delete"
                    ) { browser.deleteSpace(here.id) }
                })
        }
        return items
    }
}

/// Small questions, asked as sheets on the window.
@MainActor
enum Prompt {
    static func name(_ title: String, placeholder: String, initial: String = "", confirm: String, then: @escaping (String) -> Void) {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = placeholder
        field.stringValue = initial
        let alert = alert(title, accessory: field, focus: field, buttons: [confirm, "Cancel"])
        ask(alert) { ok in
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if ok, !name.isEmpty { then(name) }
        }
    }

    /// A new space's name, and whether it starts signed out; for when the
    /// card in the tabs can't be shown.
    static func newSpace(then: @escaping (_ name: String, _ sharesSignIns: Bool) -> Void) {
        let field = NSTextField(frame: NSRect(x: 0, y: 30, width: 260, height: 24))
        field.placeholderString = "Work"
        let fresh = NSButton(checkboxWithTitle: "Start signed out, with separate cookies", target: nil, action: nil)
        fresh.frame = NSRect(x: 0, y: 0, width: 260, height: 22)
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 56))
        box.addSubview(field)
        box.addSubview(fresh)
        let alert = alert("New Space", accessory: box, focus: field, buttons: ["Create", "Cancel"])
        alert.informativeText = "A separate set of tabs, signed in to the same sites as your other spaces unless it starts fresh."
        ask(alert) { ok in
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if ok, !name.isEmpty { then(name, fresh.state != .on) }
        }
    }

    static func confirm(_ title: String, detail: String, confirm: String, then: @escaping () -> Void) {
        let alert = alert(title, buttons: [confirm, "Cancel"])
        alert.informativeText = detail
        alert.buttons.first?.hasDestructiveAction = true
        ask(alert) { if $0 { then() } }
    }

    static func folder(then: @escaping (URL?) -> Void) {
        guard let window = AppDelegate.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use for This Space"
        panel.message = "This space's downloads will be saved here. Cancel leaves it as it is."
        panel.beginSheetModal(for: window) { answer in
            if answer == .OK, let folder = panel.url { then(folder) }
        }
    }

    private static func alert(_ title: String, accessory: NSView? = nil, focus: NSView? = nil, buttons: [String]) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.accessoryView = accessory
        buttons.forEach { alert.addButton(withTitle: $0) }
        alert.window.initialFirstResponder = focus
        return alert
    }

    /// As a sheet on the window, or on its own without one. `done` hears
    /// whether the first button was pressed.
    private static func ask(_ alert: NSAlert, _ done: @escaping (Bool) -> Void) {
        guard let window = AppDelegate.window else { return done(alert.runModal() == .alertFirstButtonReturn) }
        alert.beginSheetModal(for: window) { done($0 == .alertFirstButtonReturn) }
    }
}
