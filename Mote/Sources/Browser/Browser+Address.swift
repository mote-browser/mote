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
        if assistantLeads, MentionMenu.query(in: typed) != nil { return ([], nil) }
        guard !typed.trimmingCharacters(in: .whitespaces).isEmpty else { return ([], nil) }
        var list = history.suggestions(for: typed, limit: 3)
        // Where the assistant leads, Return asks rather than searches, so
        // searching isn't offered (⌘J switches back to it).
        if !assistantLeads, Address.url(from: typed) == nil, let search = searchURL(for: typed) {
            list.append(Suggestion(key: typed, title: prefs.engine.name(custom: prefs.customEngine), url: search, kind: .search))
        }
        // A question isn't finished for it as an address.
        if assistantLeads { return (list, nil) }
        return (list, history.completion(for: typed, among: list.filter { $0.kind != .open }))
    }

    /// The new tab's composer asks the assistant on Return, rather than
    /// searching with the engine.
    var assistantLeads: Bool { active?.isStart == true && !field.switching && field.asksAssistant }

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
    /// Return. `searching`: go or search even where the assistant leads.
    func submit(searching: Bool = false) {
        if !searching, field.input.asks(assistantLeads: assistantLeads, address: Address.url(from:)) { return ask() }
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

    /// What's typed goes to the assistant instead of the search engine, in a
    /// chat that takes over a new tab, or opens in one: Return where the
    /// assistant leads, or the composer's send button.
    func ask() {
        let text = field.typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return field.refuse() }
        guard !field.capturingMentionContext else { return }
        let staged = field.stagedMentions
        guard !staged.isEmpty else { return startAssistantChat(text, with: []) }
        guard assistantLeads, let source = active, source.isStart else {
            field.refuse()
            return
        }
        let typed = field.typed
        let sourceID = source.id
        let selected = staged.compactMap { mention in
            tab(mention.id).map { (mention: mention, tab: $0) }
        }
        guard selected.count == staged.count,
            selected.allSatisfy({ $0.tab.address == $0.mention.url && PageSharing.canShare($0.mention.url) && !$0.tab.loading })
        else {
            field.refuse()
            announce("A selected page is unavailable or still loading")
            return
        }

        field.capturingMentionContext = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { field.capturingMentionContext = false }
            var contexts: [PageContext] = []
            for target in selected {
                guard isCurrentMentionAsk(typed: typed, staged: staged, sourceID: sourceID),
                    let context = await target.tab.capturePageContext(),
                    tab(target.mention.id) === target.tab, target.tab.address == target.mention.url,
                    context.url == target.mention.url, context.title == target.tab.title, !target.tab.loading
                else {
                    field.refuse()
                    announce("A selected page changed while it was being read; try again")
                    return
                }
                contexts.append(context)
            }
            guard isCurrentMentionAsk(typed: typed, staged: staged, sourceID: sourceID) else { return }
            startAssistantChat(text, with: contexts)
        }
    }

    private func isCurrentMentionAsk(typed: String, staged: [AddressEntry.StagedMention], sourceID: Tab.ID) -> Bool {
        assistantLeads && activeID == sourceID && active?.isStart == true && field.typed == typed && field.stagedMentions == staged
    }

    private func startAssistantChat(_ text: String, with contexts: [PageContext]) {
        let chat = Conversation()
        for context in contexts { chat.mention(context) }
        // Private tabs keep nothing.
        if active?.shy != true { Assistant.shared.keep(chat) }
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
        writeSession()
    }

    /// Every kept chat, in a tab: the one already showing them, this one when
    /// it is a new tab, or a new one.
    func showChats() {
        if let tab = tabs.first(where: { $0.chats && $0.isBlank }) { return select(tab) }
        if let tab = active, tab.isStart {
            tab.chats = true
            editing = false
            field.clear()
        } else {
            let tab = Tab()
            tab.chats = true
            show(tab, adopting: true)
        }
    }

    /// A kept chat: the tab already showing it, or this one when it is a new
    /// tab, or a new one.
    func open(chat id: UUID) {
        if let tab = tabs.first(where: { $0.chat?.id == id && $0.isBlank }) { return select(tab) }
        guard let chat = Assistant.shared.reopen(id) else { return }
        // From the list of chats, the chat takes the list's place.
        if let tab = active, tab.isBlank, tab.chat == nil, !tab.shy {
            tab.chats = false
            tab.chat = chat
            editing = false
            field.clear()
        } else {
            let tab = Tab()
            tab.chat = chat
            show(tab, adopting: true)
        }
        writeSession()
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
