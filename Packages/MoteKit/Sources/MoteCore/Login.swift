import Foundation

/// A saved sign-in for a site.
public struct Login: Identifiable, Equatable, Hashable, Sendable {
    public var host: String
    public var user: String
    public var password: String
    /// When it was last used, if known; lists put the most recent first.
    public var used: Date?
    /// Saved from a plain-HTTP page. Only these are filled into HTTP pages, so
    /// an HTTPS site's password never reaches a page anyone could have changed.
    public var clear: Bool

    public var id: String { host + "\u{1}" + user }

    public init(host: String, user: String, password: String, used: Date? = nil, clear: Bool = false) {
        self.host = host
        self.user = user
        self.password = password
        self.used = used
        self.clear = clear
    }

    /// Logins for `host` and for other hosts on the same site
    /// (`accounts.example.com` and `example.com`; the keychain only matches
    /// hosts exactly), most recently used first. `site` maps a host to its
    /// registrable domain.
    public static func matching(_ host: String, in logins: [Login], site: (String) -> String) -> [Login] {
        let domain = site(host)
        let exact = logins.filter { $0.host == host }
        let wider = logins.filter { $0.host != host && site($0.host) == domain }
        return (exact + wider).sorted { ($0.used ?? .distantPast) > ($1.used ?? .distantPast) }
    }

    /// The order of the Passwords list: by site, then by account.
    public static func listed(_ logins: [Login]) -> [Login] {
        logins.sorted { ($0.host, $0.user) < ($1.host, $1.user) }
    }
}

extension Address {
    /// The site host in something typed or exported as a site: "example.com",
    /// "https://www.example.com/login". Empty when there is none.
    public static func siteHost(typed text: String) -> String {
        let text = text.trimmingCharacters(in: .whitespaces)
        return siteHost(of: URL(string: text.contains("://") ? text : "https://" + text)) ?? ""
    }
}

/// Reading a passwords export from another browser or password manager.
public enum PasswordExport {
    public struct Result: Equatable, Sendable {
        public var logins: [Login] = []
        /// Rows without a site or a password.
        public var skipped = 0
    }

    /// Column names used by Chrome, Google Password Manager, Firefox,
    /// Bitwarden and 1Password exports.
    static let siteColumns = ["url", "login_uri", "website", "site"]
    static let userColumns = ["username", "login_username", "user", "email"]
    static let passwordColumns = ["password", "login_password"]

    public static func read(csv text: String) -> Result {
        var rows = CSV.rows(text)
        guard !rows.isEmpty else { return Result() }
        let header = rows.removeFirst().map { $0.lowercased() }
        func column(_ names: [String]) -> Int? { header.firstIndex(where: names.contains) }
        guard let siteAt = column(siteColumns), let userAt = column(userColumns), let passwordAt = column(passwordColumns)
        else { return Result(skipped: rows.count) }

        var result = Result()
        for row in rows {
            guard row.indices.contains(max(siteAt, userAt, passwordAt)) else {
                result.skipped += 1
                continue
            }
            let site = row[siteAt]
            let host = Address.siteHost(typed: site)
            guard !host.isEmpty, !row[passwordAt].isEmpty else {
                result.skipped += 1
                continue
            }
            let clear = site.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("http://")
            result.logins.append(Login(host: host, user: row[userAt], password: row[passwordAt], clear: clear))
        }
        return result
    }
}

/// Comma-separated values as RFC 4180 has them: quoted fields, doubled
/// quotes inside them, and line breaks inside quotes. Blank lines are dropped.
public enum CSV {
    public static func rows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var chars = text.makeIterator()
        var pending = chars.next()

        func endRow() {
            row.append(field)
            field = ""
            if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
            row = []
        }

        while let char = pending {
            pending = chars.next()
            switch (quoted, char) {
            case (true, "\""):
                // A doubled quote is a quote; a single one ends the field.
                if pending == "\"" {
                    field.append("\"")
                    pending = chars.next()
                } else {
                    quoted = false
                }
            case (true, _): field.append(char)
            case (false, "\""): quoted = true
            case (false, ","):
                row.append(field)
                field = ""
            case (false, "\n"), (false, "\r\n"), (false, "\r"): endRow()
            case (false, _): field.append(char)
            }
        }
        endRow()
        return rows
    }
}
