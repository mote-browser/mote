import Foundation
import LocalAuthentication
import MoteCore
import Security

/// Saved passwords, kept in the macOS keychain as internet passwords under
/// Mote's label and nowhere else: never on disk, never in a log, and never
/// cached in memory. (Safari's own passwords can't be read by other browsers.)
enum PasswordStore {
    // MARK: - Reading

    /// Logins saved for exactly this host.
    static func logins(for host: String) -> [Login] {
        Keychain.items(server: host).compactMap(\.login)
    }

    /// Logins for the host and other hosts on the same site, most recent
    /// first. Only the matching items' passwords are read.
    static func logins(matching host: String) -> [Login] {
        let domain = registrable(host)
        let items = Keychain.items().filter { $0.server == host || registrable($0.server) == domain }
        return Login.matching(host, in: items.compactMap(\.login), site: registrable)
    }

    /// Every saved login, by site and account.
    static func all() -> [Login] {
        Login.listed(Keychain.items().compactMap(\.login))
    }

    // MARK: - Writing

    /// Saves or updates a login. Fails for an empty site or password, or when
    /// the keychain says no.
    @discardableResult
    static func save(_ login: Login) -> Bool {
        guard !login.host.isEmpty, !login.password.isEmpty else { return false }
        return Keychain.save(login)
    }

    @discardableResult
    static func save(host: String, user: String, password: String, used: Date? = nil, clear: Bool = false) -> Bool {
        save(Login(host: host, user: user, password: password, used: used, clear: clear))
    }

    /// Notes that the login was just used.
    static func touch(_ login: Login) {
        var used = login
        used.used = Date()
        save(used)
    }

    static func forget(host: String, user: String) {
        Keychain.delete(server: host, account: user)
    }

    /// Brings in a passwords CSV export. The file itself is not kept.
    static func take(csv text: String) -> (kept: Int, skipped: Int) {
        let read = PasswordExport.read(csv: text)
        let kept = read.logins.filter(save).count
        return (kept, read.skipped + read.logins.count - kept)
    }

    // MARK: - Sites never to offer saving for

    private static let neverKey = "passwords.never"

    static var never: Set<String> {
        get { Set(Storage.settings.stringArray(forKey: neverKey) ?? []) }
        set { Storage.settings.set(newValue.sorted(), forKey: neverKey) }
    }

    static func never(_ host: String) { never.insert(host) }
    static func isNever(_ host: String) -> Bool { never.contains(host) || never.contains(registrable(host)) }

    // MARK: - Sites

    /// The registrable domain: `example.com` for `accounts.example.com`,
    /// `bbc.co.uk` for itself.
    static func registrable(_ host: String) -> String {
        RegistrableDomain.of(host, isPublicSuffix: Passkeys.publicSuffix.map { test in { test($0 as CFString) } })
    }

    nonisolated static func host(of text: String) -> String { Address.siteHost(typed: text) }

    // MARK: - Proving it's you

    /// Asks for Touch ID, a watch or the account password before a password
    /// is shown or copied. A Mac with no way to ask (no account password) lets it through.
    static func prove(_ reason: String, _ done: @escaping (Bool) -> Void) {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return done(true) }
        Task { done((try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false) }
    }
}

/// Mote's internet-password items in the keychain.
private enum Keychain {
    /// Every item carries this label. Test worlds use their own, so their
    /// items never mix with the real ones.
    static let label = Storage.world.map { "Mote (\($0))" } ?? "Mote"

    /// An item's attributes, without its secret.
    struct Item {
        let server: String
        let account: String
        let used: Date?
        let clear: Bool

        /// The item with its password read, or nil if it can't be.
        var login: Login? {
            secret(server: server, account: account).map {
                Login(host: server, user: account, password: $0, used: used, clear: clear)
            }
        }
    }

    private static func base(server: String? = nil, account: String? = nil) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassInternetPassword, kSecAttrLabel as String: label]
        if let server { query[kSecAttrServer as String] = server }
        if let account { query[kSecAttrAccount as String] = account }
        return query
    }

    /// Lists items by their attributes. The keychain can't return several
    /// items' secrets in one query (errSecParam), so those are read one by one.
    static func items(server: String? = nil) -> [Item] {
        var query = base(server: server)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var found: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &found)
        guard status == errSecSuccess, let rows = found as? [[String: Any]] else {
            // The list can't show this apart from an empty keychain, so say it here.
            if status != errSecItemNotFound { NSLog("Passwords: keychain list failed (%d)", status) }
            return []
        }
        return rows.compactMap { row in
            guard let server = row[kSecAttrServer as String] as? String, let account = row[kSecAttrAccount as String] as? String
            else { return nil }
            // The last use is kept in the comment, as a Unix time.
            let used = (row[kSecAttrComment as String] as? String).flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
            let clear = row[kSecAttrProtocol as String] as? String == kSecAttrProtocolHTTP as String
            return Item(server: server, account: account, used: used, clear: clear)
        }
    }

    static func secret(server: String, account: String) -> String? {
        var query = base(server: server, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &found)
        guard status == errSecSuccess, let data = found as? Data else {
            if status != errSecItemNotFound { NSLog("Passwords: keychain read failed (%d)", status) }
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Updates the item, or adds it. The label is part of the lookup so
    /// another app's item for the same server and account (git's github.com
    /// token, say) is never touched; the HTML-form kind keeps the new item
    /// apart from such items too, or adding it fails as a duplicate.
    static func save(_ login: Login) -> Bool {
        let lookup = base(server: login.host, account: login.user)
        var fields: [String: Any] = [
            kSecValueData as String: Data(login.password.utf8),
            kSecAttrLabel as String: label,
            kSecAttrAuthenticationType as String: kSecAttrAuthenticationTypeHTMLForm,
            kSecAttrProtocol as String: login.clear ? kSecAttrProtocolHTTP : kSecAttrProtocolHTTPS,
        ]
        if let used = login.used { fields[kSecAttrComment as String] = String(used.timeIntervalSince1970) }

        switch SecItemUpdate(lookup as CFDictionary, fields as CFDictionary) {
        case errSecSuccess: return true
        case errSecItemNotFound:
            var item = lookup.merging(fields) { $1 }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        default: return false
        }
    }

    static func delete(server: String, account: String) {
        SecItemDelete(base(server: server, account: account) as CFDictionary)
    }
}
