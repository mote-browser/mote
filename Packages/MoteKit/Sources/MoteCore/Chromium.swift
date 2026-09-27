import CommonCrypto
import Foundation

/// How Chromium-based browsers (Chrome, Arc, Dia, Brave, Edge…) keep their
/// data on a Mac, read without touching their files: the caller hands over
/// what it read.
public enum Chromium {
    // MARK: - Passwords

    /// The key for a profile's passwords, from the "<Name> Safe Storage"
    /// passphrase in the keychain: PBKDF2-HMAC-SHA1, salt "saltysalt", 1003
    /// rounds, 16 bytes.
    public static func key(passphrase: String) -> [UInt8] {
        var key = [UInt8](repeating: 0, count: 16)
        let salt = Array("saltysalt".utf8)
        _ = passphrase.withCString { pass in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2), pass, strlen(pass), salt, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, &key, key.count)
        }
        return key
    }

    /// A stored password. "v10" blobs are AES-128-CBC with an IV of sixteen
    /// spaces; newer versions put a 32-byte hash of the site before the text.
    /// Very old profiles kept passwords as plain text.
    public static func decrypt(_ blob: Data, key: [UInt8]) -> String? {
        guard blob.starts(with: Data("v10".utf8)) else { return String(data: blob, encoding: .utf8) }
        guard let plain = aes(decrypting: Array(blob.dropFirst(3)), key: key) else { return nil }
        return String(data: plain, encoding: .utf8) ?? (plain.count > 32 ? String(data: plain.dropFirst(32), encoding: .utf8) : nil)
    }

    static let iv = [UInt8](repeating: 0x20, count: 16)

    static func aes(decrypting input: [UInt8], key: [UInt8]) -> Data? {
        crypt(CCOperation(kCCDecrypt), input, key: key)
    }

    static func aes(encrypting input: [UInt8], key: [UInt8]) -> Data? {
        crypt(CCOperation(kCCEncrypt), input, key: key)
    }

    private static func crypt(_ operation: CCOperation, _ input: [UInt8], key: [UInt8]) -> Data? {
        var output = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var written = 0
        let status = CCCrypt(
            operation, CCAlgorithm(kCCAlgorithmAES128), CCOptions(kCCOptionPKCS7Padding), key, key.count, iv, input,
            input.count, &output, output.count, &written)
        return status == kCCSuccess ? Data(output.prefix(written)) : nil
    }

    /// A row of a profile's "Login Data" database.
    public struct LoginRow: Sendable {
        public var origin: String
        public var user: String
        public var blob: Data
        /// On the never-save list.
        public var never: Bool
        public var used: Date?

        public init(origin: String, user: String, blob: Data, never: Bool, used: Date?) {
            self.origin = origin
            self.user = user
            self.blob = blob
            self.never = never
            self.used = used
        }
    }

    public struct Passwords: Equatable, Sendable {
        public var logins: [Login] = []
        /// Sites on the browser's never-save list.
        public var never: [String] = []
    }

    /// The logins in some profiles' rows, each site and account once.
    public static func passwords(in rows: [LoginRow], key: [UInt8]) -> Passwords {
        var found = Passwords()
        var seen = Set<String>()
        for row in rows {
            let host = Address.siteHost(typed: row.origin)
            guard !host.isEmpty else { continue }
            if row.never {
                found.never.append(host)
                continue
            }
            guard let password = decrypt(row.blob, key: key), !password.isEmpty else { continue }
            let clear = row.origin.lowercased().hasPrefix("http://")
            let login = Login(host: host, user: row.user, password: password, used: row.used, clear: clear)
            if seen.insert(login.id).inserted { found.logins.append(login) }
        }
        return found
    }

    // MARK: - Times

    /// Chromium counts microseconds from 1601-01-01 UTC; zero means never.
    public static func date(_ microseconds: Int64) -> Date? {
        microseconds > 0 ? Date(timeIntervalSince1970: Double(microseconds) / 1_000_000 - 11_644_473_600) : nil
    }

    // MARK: - Bookmarks

    /// A profile's "Bookmarks" JSON: the bookmarks bar's items at the top,
    /// then "Other" and "Mobile" as folders. Only web addresses are kept.
    public static func bookmarks(json: Data) -> [Bookmark] {
        guard let file = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
            let roots = file["roots"] as? [String: Any]
        else { return [] }
        func children(of root: String) -> [Bookmark] {
            nodes((roots[root] as? [String: Any])?["children"] as? [[String: Any]] ?? [])
        }
        var found = children(of: "bookmark_bar")
        for (root, name) in [("other", "Other"), ("synced", "Mobile")] {
            let inside = children(of: root)
            if !inside.isEmpty { found.append(.folder(name, inside)) }
        }
        return found
    }

    private static func nodes(_ entries: [[String: Any]]) -> [Bookmark] {
        entries.compactMap { entry in
            let name = entry["name"] as? String ?? ""
            switch entry["type"] as? String {
            case "folder":
                return .folder(name, nodes(entry["children"] as? [[String: Any]] ?? []))
            case "url":
                guard let url = (entry["url"] as? String).flatMap(URL.init(string:)), ["http", "https"].contains(url.scheme)
                else { return nil }
                return .site(name, url)
            default:
                return nil
            }
        }
    }

    // MARK: - Icons

    /// Pages whose icon stands for a site: the page itself, then the site's root.
    public static func iconPages(for url: URL) -> [String] {
        guard let scheme = url.scheme, let host = url.host() else { return [url.absoluteString] }
        return [url.absoluteString, "\(scheme)://\(host)/"]
    }

    /// One address per site, up to `limit`, for looking up icons.
    public static func iconSites(_ urls: [URL], limit: Int) -> [(host: String, url: URL)] {
        var seen = Set<String>()
        var sites: [(host: String, url: URL)] = []
        for url in urls {
            guard sites.count < limit, let host = url.host()?.lowercased(), seen.insert(host).inserted else { continue }
            sites.append((host, url))
        }
        return sites
    }
}
