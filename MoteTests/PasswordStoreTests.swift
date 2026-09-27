import Foundation
import MoteCore
import Testing

@testable import Mote

/// Real keychain round trips, under the test world's own label.
@Suite("Passwords in the keychain", .serialized)
@MainActor
struct PasswordStoreTests {
    /// A made-up site per run, so nothing clashes with other runs or real items.
    private let site = "mote-test-\(UUID().uuidString.prefix(8).lowercased()).example"

    @Test("A saved login reads back, updates in place and goes when forgotten")
    func roundTrip() {
        defer { PasswordStore.forget(host: site, user: "me") }
        #expect(PasswordStore.save(host: site, user: "me", password: "first"))
        #expect(PasswordStore.logins(for: site).map(\.password) == ["first"])

        #expect(PasswordStore.save(host: site, user: "me", password: "second", clear: true))
        let saved = PasswordStore.logins(for: site)
        #expect(saved.count == 1)
        #expect(saved.first?.password == "second")
        #expect(saved.first?.clear == true)

        PasswordStore.forget(host: site, user: "me")
        #expect(PasswordStore.logins(for: site).isEmpty)
    }

    @Test("A sub-host finds the site's logins, most recently used first")
    func matching() throws {
        let sub = "accounts." + site
        defer {
            PasswordStore.forget(host: site, user: "old")
            PasswordStore.forget(host: sub, user: "new")
        }
        #expect(PasswordStore.save(host: site, user: "old", password: "x", used: Date(timeIntervalSince1970: 1)))
        #expect(PasswordStore.save(host: sub, user: "new", password: "y", used: Date(timeIntervalSince1970: 2)))
        #expect(PasswordStore.logins(matching: sub).map(\.user) == ["new", "old"])
        let old = try #require(PasswordStore.logins(for: site).first)
        PasswordStore.touch(old)
        #expect(PasswordStore.logins(matching: sub).first?.user == "old")
    }

    @Test("Empty sites and passwords are refused")
    func refused() {
        #expect(!PasswordStore.save(host: "", user: "me", password: "x"))
        #expect(!PasswordStore.save(host: site, user: "me", password: ""))
    }

    @Test("A CSV export is brought in and its bad rows counted")
    func csv() {
        defer { PasswordStore.forget(host: site, user: "csv") }
        let result = PasswordStore.take(csv: "url,username,password\nhttps://\(site)/login,csv,pw\n,x,y\n")
        #expect(result.kept == 1)
        #expect(result.skipped == 1)
        #expect(PasswordStore.logins(for: site).first?.user == "csv")
    }
}
