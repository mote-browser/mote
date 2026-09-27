import AppKit
import MoteCore
import Observation
import UniformTypeIdentifiers

/// Saved passwords as the window sees them: the offer to save one after a
/// sign-in, the accounts listed under a focused sign-in field, and the
/// Passwords panel's list. The keychain itself is PasswordStore.
@MainActor
@Observable
final class Logins {
    /// A sign-in waiting for the user to say whether to keep it.
    struct Offer: Equatable {
        let login: Login
        /// The same account is saved with another password.
        let changed: Bool
    }

    /// Accounts listed under a focused sign-in field. Nothing is filled until
    /// one is picked.
    struct Choices: Equatable {
        let tab: Tab.ID
        /// The field's frame, to place the list under it.
        let spot: CGRect
        let logins: [Login]
        /// The site the list was made for; a pick fills only a page still on it.
        let host: String
        /// The page is plain HTTP.
        let clear: Bool
    }

    struct Site {
        let host: String
        let logins: [Login]
    }

    private(set) var offer: Offer?
    private(set) var choices: Choices?

    /// Whether the Passwords panel is shown.
    var managing = false {
        didSet { if managing { reload() } }
    }
    private(set) var saved: [Login] = []
    /// The panel's search text.
    var query = ""

    /// Saved logins grouped by site, filtered by `query`.
    var sites: [Site] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = needle.isEmpty ? saved : saved.filter { $0.host.contains(needle) || $0.user.lowercased().contains(needle) }
        return Dictionary(grouping: shown, by: \.host)
            .sorted { $0.key < $1.key }
            .map { Site(host: $0.key, logins: $0.value.sorted { $0.user < $1.user }) }
    }

    /// Set after a pick so the list doesn't come back for the same field;
    /// cleared when focus leaves the sign-in fields.
    @ObservationIgnored private var filled: Tab.ID?
    /// Hiding the list waits a moment: clicking a row can blur the field first.
    @ObservationIgnored private var hiding: Task<Void, Never>?

    @ObservationIgnored private let say: (String) -> Void
    @ObservationIgnored private let tab: (Tab.ID) -> Tab?

    init(say: @escaping (String) -> Void, tab: @escaping (Tab.ID) -> Tab?) {
        self.say = say
        self.tab = tab
    }

    // MARK: - After a sign-in

    /// A page submitted a sign-in. Offers to save it unless it is already
    /// saved (then only its last use is updated).
    func signedIn(host: String, user: String, password: String, clear: Bool) {
        guard !password.isEmpty, !PasswordStore.isNever(host) else { return }
        let known = PasswordStore.logins(for: host)
        if var same = known.first(where: { $0.user == user && $0.password == password }) {
            same.clear = clear
            PasswordStore.touch(same)
            return
        }
        let next = Offer(
            login: Login(host: host, user: user, password: password, used: nil, clear: clear),
            changed: known.contains { $0.user == user })
        if offer != next { offer = next }
    }

    func keepOffer() {
        guard let login = offer?.login, let changed = offer?.changed else { return }
        offer = nil
        guard PasswordStore.save(host: login.host, user: login.user, password: login.password, used: Date(), clear: login.clear)
        else { return say("The keychain refused it") }
        reload()
        say(changed ? "Password updated for \(login.host)" : "Password saved for \(login.host)")
    }

    func dropOffer() { offer = nil }

    /// Never offer to save passwords for this site.
    func neverOffer() {
        guard let host = offer?.login.host else { return }
        PasswordStore.never(host)
        offer = nil
        say("Never for \(host)")
    }

    // MARK: - Under a sign-in field

    /// A sign-in field in `tab` gained focus at `spot`, or lost it (nil).
    func fieldFocused(in tab: Tab, at spot: CGRect?, listing: Bool) {
        hiding?.cancel()
        guard let spot else {
            if filled == tab.id { filled = nil }
            guard choices?.tab == tab.id else { return }
            hiding = Task { [weak self] in
                try? await Task.sleep(for: .seconds(0.2))
                guard !Task.isCancelled, let self, choices?.tab == tab.id else { return }
                choices = nil
            }
            return
        }
        guard listing, filled != tab.id, let host = Address.siteHost(of: tab.address) else { return }
        // A plain-HTTP page may have been changed in transit, so it only sees
        // logins saved from HTTP pages, never the HTTPS site's.
        let clear = tab.address?.scheme?.lowercased() == "http"
        let known = PasswordStore.logins(matching: host).filter { !clear || $0.clear }.prefix(5)
        choices = known.isEmpty ? nil : Choices(tab: tab.id, spot: spot, logins: Array(known), host: host, clear: clear)
    }

    func choose(_ login: Login) {
        hiding?.cancel()
        guard let list = choices, let tab = tab(list.tab) else { return }
        choices = nil
        // The page may have moved on while the list was up; never fill another site.
        guard Address.siteHost(of: tab.address) == list.host, (tab.address?.scheme?.lowercased() == "http") == list.clear
        else { return }
        filled = tab.id
        tab.fill(user: login.user, password: login.password) { [weak self] worked in
            if !worked { self?.say("Couldn't find the sign-in fields anymore") }
        }
        PasswordStore.touch(login)
    }

    func dropChoices() { choices = nil }

    // MARK: - The Passwords panel

    func reload() { saved = PasswordStore.all() }

    func add(host: String, user: String, password: String) {
        guard PasswordStore.save(host: host, user: user, password: password) else { return say("The keychain refused it") }
        reload()
        say("Kept for \(host)")
    }

    func forget(_ login: Login) {
        PasswordStore.forget(host: login.host, user: login.user)
        reload()
    }

    /// Copies a password after the user proves who they are. It goes to this
    /// Mac's pasteboard only (not Universal Clipboard), marked concealed and
    /// transient so clipboard managers skip it, and is cleared after 90
    /// seconds unless something else was copied.
    func copy(_ login: Login) {
        PasswordStore.prove("copy the password for \(login.host)") { [weak self] ok in
            guard ok else { return }
            let board = NSPasteboard.general
            board.prepareForNewContents(with: .currentHostOnly)
            board.setString(login.password, forType: .string)
            board.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
            board.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
            let copied = board.changeCount
            Task {
                try? await Task.sleep(for: .seconds(90))
                if board.changeCount == copied { board.clearContents() }
            }
            self?.say("Password copied")
        }
    }

    // MARK: - Bringing passwords in

    enum ImportTrouble: Error {
        /// macOS didn't hand over the other browser's keychain key.
        case locked
        case unreadable
    }

    /// Reads another browser's passwords off the main actor and saves them to
    /// the keychain. Returns how many were kept.
    func bring(from source: ChromiumImporter.Source) async -> Result<Int, ImportTrouble> {
        let outcome = await Task.detached(priority: .userInitiated) { Result { try ChromiumImporter.read(source) } }.value
        switch outcome {
        case .success(let found):
            let kept = found.logins.filter {
                PasswordStore.save(host: $0.host, user: $0.user, password: $0.password, used: $0.used, clear: $0.clear)
            }.count
            PasswordStore.never = PasswordStore.never.union(found.never)
            reload()
            return .success(kept)
        case .failure(ChromiumImporter.Trouble.noPassphrase):
            return .failure(.locked)
        case .failure:
            return .failure(.unreadable)
        }
    }

    /// Imports from another browser and says how it went.
    func bringAndSay(from source: ChromiumImporter.Source) async {
        switch await bring(from: source) {
        case .success(0): say("Nothing new in \(source.name)")
        case .success(let kept): say("\(kept) passwords from \(source.name)")
        case .failure(.locked): say("\(source.name) didn't give up its keychain key")
        case .failure(.unreadable): say("Nothing readable in \(source.name)")
        }
    }

    /// Imports a passwords CSV export. The file is read once and not copied.
    func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = "A passwords export, as Chrome, Dia or Google Password Manager write it."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return say("Couldn't read that file as text") }
        let result = PasswordStore.take(csv: text)
        reload()
        say(result.skipped == 0 ? "\(result.kept) passwords in the keychain" : "\(result.kept) in the keychain, \(result.skipped) skipped")
    }
}
