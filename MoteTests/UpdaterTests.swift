import Foundation
import MoteCore
import Testing

@testable import Mote

@Suite("Updater", .serialized)
@MainActor
struct UpdaterTests {
    private let suiteName = "io.github.mote-browser.updater-tests.\(UUID())"

    private func settings() -> UserDefaults {
        let settings = UserDefaults(suiteName: suiteName)!
        settings.set(false, forKey: Updater.installKey)
        return settings
    }

    private func release(_ build: Int = Updater.build + 1) -> AppRelease {
        AppRelease(
            version: "test", build: build, archive: URL(string: "https://x.test/a.zip")!,
            diskImage: URL(string: "https://x.test/a.dmg")!)
    }

    @Test("Every launch checks despite a recent successful check")
    func launch() async throws {
        let settings = settings()
        defer { settings.removePersistentDomain(forName: suiteName) }
        settings.set(Date(), forKey: "update.checked")
        var calls = 0
        let current = release(Updater.build)
        let updater = Updater(
            settings: settings, enabled: true,
            latest: {
                calls += 1; return current
            })
        updater.checkIfDue { _ in }
        _ = try await eventually { !updater.checking && calls == 1 ? true : nil }
        #expect(updater.lastChecked != nil)
        updater.checkIfDue { _ in }
        #expect(!updater.checking)
        let reopened = Updater(
            settings: settings, enabled: true,
            latest: {
                calls += 1; return current
            })
        reopened.checkIfDue { _ in }
        _ = try await eventually { !reopened.checking && calls == 2 ? true : nil }
    }

    @Test(
        "A failure preserves the last success and the available update, and reports an error",
        arguments: [URLError.Code.notConnectedToInternet, .timedOut, .badServerResponse, .cannotParseResponse])
    func failure(_ code: URLError.Code) async throws {
        let settings = settings()
        defer { settings.removePersistentDomain(forName: suiteName) }
        var failing = false
        let found = release()
        let updater = Updater(
            settings: settings, enabled: true,
            latest: {
                if failing { throw URLError(code) }
                return found
            })
        updater.checkIfDue { _ in }
        _ = try await eventually { updater.stage == .waiting(found) ? true : nil }
        let checked = settings.object(forKey: "update.checked") as? Date
        failing = true
        let result = await withCheckedContinuation { continuation in
            updater.check { continuation.resume(returning: $0) }
        }
        if case .success = result { Issue.record("A network failure must not report success") }
        #expect(updater.checkFailed)
        #expect(updater.stage == .waiting(found))
        #expect(settings.object(forKey: "update.checked") as? Date == checked)
        failing = false
        let recovered = await withCheckedContinuation { continuation in
            updater.check { continuation.resume(returning: $0) }
        }
        if case .failure = recovered { Issue.record("The next successful check must recover") }
        #expect(!updater.checkFailed)
    }

    @Test("Automatic installation announces the release before installation starts")
    func announcesBeforeInstalling() async throws {
        let settings = settings()
        defer { settings.removePersistentDomain(forName: suiteName) }
        settings.set(true, forKey: Updater.installKey)
        let found = release()
        var announced = false
        let updater = Updater(
            settings: settings, enabled: true, latest: { found },
            installer: { _ in
                throw URLError(.cannotWriteToFile)
            })
        updater.checkIfDue { [weak updater] news in
            if case .out(let release) = news {
                #expect(release == found)
                #expect(updater?.stage != .fetching(found))
                announced = true
            }
        }
        _ = try await eventually { updater.stage == .offered(found) ? true : nil }
        #expect(announced)
    }

    @Test("An unchanged waiting release is announced once per session")
    func announcesOnce() async throws {
        let found = release()
        let settings = settings()
        defer { settings.removePersistentDomain(forName: suiteName) }
        let updater = Updater(settings: settings, enabled: true, latest: { found })
        var announcements = 0
        updater.checkIfDue { if case .out = $0 { announcements += 1 } }
        _ = try await eventually { updater.stage == .waiting(found) ? true : nil }
        _ = await withCheckedContinuation { continuation in
            updater.check { continuation.resume(returning: $0) }
        }
        #expect(announcements == 1)
    }

    @Test("An overlapping check completes with an error, never a false up-to-date result")
    func overlapping() async throws {
        let settings = settings()
        defer { settings.removePersistentDomain(forName: suiteName) }
        let found = release()
        let updater = Updater(settings: settings, enabled: true, latest: { found })
        updater.checkIfDue { _ in }
        var replied = false
        updater.check { result in
            replied = true
            if case .success = result { Issue.record("An overlapping check must not report success") }
        }
        #expect(replied)
        _ = try await eventually { updater.stage == .waiting(found) ? true : nil }
    }
}
