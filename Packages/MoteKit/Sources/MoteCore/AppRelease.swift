import Foundation

/// A release named by the update feed (`appcast.json`).
public struct AppRelease: Equatable, Sendable {
    public let version: String
    /// Only ever goes up; this, not `version`, decides what is newer.
    public let build: Int
    /// The zip the updater installs.
    public let archive: URL
    /// The disk image offered when the updater can't install in place.
    public let diskImage: URL
    /// Hex SHA-256 of `archive`.
    public let sha256: String?
    /// Mote's Ed25519 signature of `archive`, base64 (UpdateSignature).
    public let signature: String?
    public let notes: String?
    public let minimumSystemVersion: String?

    public init(
        version: String,
        build: Int,
        archive: URL,
        diskImage: URL,
        sha256: String? = nil,
        signature: String? = nil,
        notes: String? = nil,
        minimumSystemVersion: String? = nil
    ) {
        self.version = version
        self.build = build
        self.archive = archive
        self.diskImage = diskImage
        self.sha256 = sha256
        self.signature = signature
        self.notes = notes
        self.minimumSystemVersion = minimumSystemVersion
    }

    /// Parses a feed. Download links must be https (or http when
    /// `allowsHTTP`, for local test feeds) and on the feed's own host, so a
    /// tampered feed can't point people at another site.
    public init?(appcast data: Data, feed: URL, allowsHTTP: Bool = false) {
        func link(_ value: Any?) -> URL? {
            guard let url = (value as? String).flatMap(URL.init(string:)),
                url.scheme == "https" || (allowsHTTP && url.scheme == "http"),
                url.host() == feed.host()
            else { return nil }
            return url
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let version = json["version"] as? String,
            let build = (json["build"] as? Int) ?? Int(json["build"] as? String ?? ""),
            let archive = link(json["url"]),
            let diskImage = link(json["dmg"])
        else { return nil }

        func text(_ key: String) -> String? {
            let value = (json[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }

        self.init(
            version: version,
            build: build,
            archive: archive,
            diskImage: diskImage,
            sha256: text("sha256")?.lowercased(),
            signature: text("signature"),
            notes: text("notes"),
            minimumSystemVersion: json["minimumSystemVersion"] as? String
        )
    }

    /// Whether this release runs on `system`: a release that needs a newer
    /// macOS is not an update for this Mac.
    public func runs(on system: OperatingSystemVersion) -> Bool {
        guard let minimumSystemVersion else { return true }
        let parts = minimumSystemVersion.split(separator: ".").map { Int($0) ?? 0 }
        let required = (parts.count > 0 ? parts[0] : 0, parts.count > 1 ? parts[1] : 0, parts.count > 2 ? parts[2] : 0)
        return (system.majorVersion, system.minorVersion, system.patchVersion) >= required
    }
}
