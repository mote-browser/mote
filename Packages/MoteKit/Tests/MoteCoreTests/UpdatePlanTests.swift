import Foundation
import Testing

@testable import MoteCore

@Suite("UpdatePlan")
struct UpdatePlanTests {
    private func release(_ build: Int, system: String? = nil) -> AppRelease {
        AppRelease(
            version: "1.\(build)", build: build, archive: URL(string: "https://x.test/a.zip")!,
            diskImage: URL(string: "https://x.test/a.dmg")!, minimumSystemVersion: system)
    }

    private let macOS26 = OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)

    @Test("A check is due after 20 hours, or always with a test feed")
    func due() {
        let now = Date()
        #expect(UpdatePlan.due(last: nil, now: now, always: false))
        #expect(!UpdatePlan.due(last: now.addingTimeInterval(-3600), now: now, always: false))
        #expect(UpdatePlan.due(last: now.addingTimeInterval(-21 * 3600), now: now, always: false))
        #expect(UpdatePlan.due(last: now, now: now, always: true))
    }

    @Test("A failed check retries after five minutes, even after a recent successful check")
    func retry() {
        let now = Date()
        let last = now.addingTimeInterval(-3600)
        #expect(!UpdatePlan.due(last: last, now: now, always: false, failed: now))
        #expect(!UpdatePlan.due(last: nil, now: now, always: false, failed: now.addingTimeInterval(-299)))
        #expect(UpdatePlan.due(last: last, now: now, always: false, failed: now.addingTimeInterval(-300)))
        #expect(UpdatePlan.due(last: last, now: now, always: true, failed: now))
    }

    @Test("Only a higher build that runs on this system counts")
    func newer() {
        #expect(UpdatePlan.newer(release(5), than: 4, system: macOS26) == release(5))
        #expect(UpdatePlan.newer(release(4), than: 4, system: macOS26) == nil)
        #expect(UpdatePlan.newer(release(5, system: "27.0"), than: 4, system: macOS26) == nil)
        #expect(UpdatePlan.newer(nil, than: 4, system: macOS26) == nil)
    }

    @Test("Installing on its own starts once, never over one in progress or done")
    func installs() {
        let found = release(5)
        #expect(UpdatePlan.next(after: found, in: .none, installsOnItsOwn: true) == (.none, .install(found)))
        #expect(UpdatePlan.next(after: found, in: .fetching(found), installsOnItsOwn: true).1 == .nothing)
        #expect(UpdatePlan.next(after: found, in: .ready(found), installsOnItsOwn: true).1 == .nothing)
        #expect(UpdatePlan.next(after: found, in: .offered(found), installsOnItsOwn: true).1 == .install(found))
    }

    @Test("Without installing on its own it waits, and says so once per release")
    func waits() {
        let found = release(5)
        #expect(UpdatePlan.next(after: found, in: .none, installsOnItsOwn: false) == (.waiting(found), .wait(found)))
        #expect(UpdatePlan.next(after: found, in: .waiting(found), installsOnItsOwn: false).1 == .nothing)
        let later = release(6)
        #expect(UpdatePlan.next(after: later, in: .waiting(found), installsOnItsOwn: false) == (.waiting(later), .wait(later)))
    }

    @Test("Nothing newer keeps an installed update, and clears the rest")
    func nothingNewer() {
        let found = release(5)
        #expect(UpdatePlan.next(after: nil, in: .ready(found), installsOnItsOwn: true).0 == .ready(found))
        #expect(UpdatePlan.next(after: nil, in: .waiting(found), installsOnItsOwn: true).0 == .none)
    }

    @Test("An install lands only if it's still the one being fetched")
    func landing() {
        let found = release(5)
        #expect(UpdatePlan.landed(found, worked: true, in: .fetching(found)) == .ready(found))
        #expect(UpdatePlan.landed(found, worked: false, in: .fetching(found)) == .offered(found))
        #expect(UpdatePlan.landed(found, worked: true, in: .none) == nil)
        #expect(UpdatePlan.landed(found, worked: true, in: .fetching(release(6))) == nil)
    }

    @Test("The signing requirement names the team and the app")
    func requirement() {
        let text = UpdatePlan.requirement(team: "ABCDE12345", identifier: "io.test.app")
        #expect(text.hasPrefix("anchor apple generic and identifier \"io.test.app\""))
        #expect(text.hasSuffix("certificate leaf[subject.OU] = \"ABCDE12345\""))
    }

    @Test("SHA-256 over chunks matches the known value")
    func hashing() {
        var chunks = [Data("ab".utf8), Data("c".utf8)]
        let hex = UpdatePlan.sha256 { chunks.isEmpty ? nil : chunks.removeFirst() }
        #expect(hex == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
