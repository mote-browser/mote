import Foundation
import Testing

@testable import MoteCore

@Suite("AppRelease")
struct AppReleaseTests {
    private let feed = URL(string: "https://mote.example.com/appcast.json")!

    private func appcast(_ fields: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: fields)
    }

    private var valid: [String: Any] {
        [
            "version": "1.2.0",
            "build": 202609270900,
            "url": "https://mote.example.com/Mote.zip",
            "dmg": "https://mote.example.com/Mote.dmg",
            "sha256": " ABCDEF ",
            "signature": "c2lnbmVk",
            "notes": "  ",
            "minimumSystemVersion": "14.0",
        ]
    }

    @Test("A valid feed is parsed")
    func parsesValidFeed() throws {
        let release = try #require(AppRelease(appcast: try appcast(valid), feed: feed))
        #expect(release.version == "1.2.0")
        #expect(release.build == 202609270900)
        #expect(release.archive.lastPathComponent == "Mote.zip")
        #expect(release.sha256 == "abcdef")
        #expect(release.signature == "c2lnbmVk")
        #expect(release.notes == nil)
    }

    @Test("The build number may be a string")
    func buildAsString() throws {
        var fields = valid
        fields["build"] = "42"
        #expect(AppRelease(appcast: try appcast(fields), feed: feed)?.build == 42)
    }

    @Test("Links to another host are refused")
    func refusesOtherHost() throws {
        var fields = valid
        fields["dmg"] = "https://evil.example.net/Mote.dmg"
        #expect(AppRelease(appcast: try appcast(fields), feed: feed) == nil)
    }

    @Test("Plain http is refused unless allowed")
    func refusesHTTP() throws {
        var fields = valid
        fields["url"] = "http://mote.example.com/Mote.zip"
        #expect(AppRelease(appcast: try appcast(fields), feed: feed) == nil)
        #expect(AppRelease(appcast: try appcast(fields), feed: feed, allowsHTTP: true) != nil)
    }

    @Test("Garbage is not a release")
    func refusesGarbage() {
        #expect(AppRelease(appcast: Data("not json".utf8), feed: feed) == nil)
    }

    @Test(
        "Minimum system version",
        arguments: [
            ("14.0", OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0), true),
            ("14.2", OperatingSystemVersion(majorVersion: 14, minorVersion: 1, patchVersion: 9), false),
            ("15", OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0), true),
            ("26.1.2", OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 1), false),
            ("26.1.2", OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 2), true),
        ])
    func minimumSystem(required: String, system: OperatingSystemVersion, runs: Bool) {
        let release = AppRelease(version: "1", build: 1, archive: feed, diskImage: feed, minimumSystemVersion: required)
        #expect(release.runs(on: system) == runs)
    }
}
