import AppKit
import MoteAI
import MoteCore

// The address field's actions: what it suggests, ⌘L, ⌘K and Return.
extension Browser {
    func searchURL(for text: String) -> URL? {
        SearchEngine.url(for: text, template: prefs.engine.template(custom: prefs.customEngine))
    }

    /// An address, or failing that a search.
    func destination(for typed: String) -> URL? {
        Address.url(from: typed) ?? searchURL(for: typed)
    }

    /// Suggestions for the field. The switcher lists open tabs; otherwise up
    /// to three places from history, plus a search when the text can't be an
    /// address. Open tabs are left to ⌘K to keep the list short.
    func suggestions(for typed: String, switching: Bool) -> ([Suggestion], String?) {
        if switching { return (openPages(matching: typed), nil) }
        guard !typed.trimmingCharacters(in: .whitespaces).isEmpty else { return ([], nil) }
        var list = history.suggestions(for: typed, limit: 3)
        if Address.url(from: typed) == nil, let search = searchURL(for: typed) {
            list.append(Suggestion(key: typed, title: prefs.engine.name(custom: prefs.customEngine), url: search, kind: .search))
        }
        return (list, history.completion(for: typed, among: list.filter { $0.kind != .open }))
    }

    /// Open tabs other than the active one, most recently seen first,
    /// matching the text by title or address.
    private func openPages(matching typed: String) -> [Suggestion] {
        let needle = typed.trimmingCharacters(in: .whitespaces).lowercased()
        return
            tabs
            .filter { $0.id != activeID && !$0.isBlank }
            .filter { tab in
                needle.isEmpty || tab.label.lowercased().contains(needle)
                    || (tab.address.map(Address.displayString(for:)) ?? "").contains(needle)
            }
            .sorted { $0.touched > $1.touched }
            .prefix(needle.isEmpty ? 6 : 3)
            .compactMap { tab in
                tab.address.map {
                    Suggestion(key: tab.label, title: Address.displayString(for: $0), url: $0, kind: .open, tab: tab.id)
                }
            }
    }

    /// ⌘L: the field with the current address in it.
    func edit() {
        field.switching = false
        field.typed = active?.address?.absoluteString ?? ""
        editing = true
        field.askFocus()
    }

    /// Escape or a click outside. A blank tab keeps its field; there is no
    /// page behind it.
    func dismiss() {
        field.switching = false
        field.cycling = false
        guard active?.isStart == false else { return }
        editing = false
        field.clear()
    }

    /// ⌘K: the tab switcher.
    func summon() {
        reviewing = false
        cancelTabEdit()
        field.startSwitching()
        editing = true
        field.askFocus()
    }

    /// ⌘K again while ⌘ is held: the next tab.
    func stepSummon() {
        field.cycling = true
        field.walk(1)
    }

    /// ⌘ let go after cycling: opens the picked tab.
    func landSummon() {
        guard field.cycling else { return }
        field.cycling = false
        if field.picked != nil { submit() }
    }

    /// Return.
    func submit() {
        switch field.submit(address: Address.url(from:), destination: destination(for:)) {
        case .switchTo(let id, let url):
            if let tab = tab(id) { select(tab) } else if let tab = active ?? tabs.first { go(tab, to: url) }
        case .go(let url):
            if let tab = active ?? tabs.first { go(tab, to: url) }
        case .close:
            editing = false
        case .refuse:
            field.refuse()
        }
    }

    /// ⌘Return: what's typed goes to the assistant instead of the search
    /// engine, in a chat that takes over a new tab, or opens in one.
    func ask() {
        let text = field.typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return field.refuse() }
        let chat = Conversation()
        Assistant.shared.ask(text, in: chat)
        if let tab = active, tab.isStart {
            tab.chat = chat
        } else {
            let tab = Tab(shy: active?.shy ?? false)
            tab.chat = chat
            show(tab, adopting: true)
        }
        editing = false
        field.clear()
    }

    /// A clicked suggestion opens directly, without moving the keyboard pick,
    /// so a list appearing under a still pointer doesn't change the field.
    func take(_ offer: Suggestion) {
        field.switching = false
        if let id = offer.tab, let tab = tab(id) {
            select(tab)
        } else if let tab = active ?? tabs.first {
            go(tab, to: offer.url)
        }
    }
}
