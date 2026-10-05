import AppKit
import Combine
import MoteCore
import Security

/// Updates from a JSON feed. A newer build is downloaded, its signature
/// checked against the update key built into this copy (UpdateSignature),
/// and put in place of this bundle; it opens the next time Mote does, and
/// Mote never restarts by itself. Only the bundle changes: settings,
/// Application Support and the keychain stay. Without MOTE_FEED_URL and
/// MOTE_UPDATE_KEY at build time there's no updating. The decisions are
/// UpdatePlan's.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    typealias Stage = UpdatePlan.Stage

    @Published private(set) var stage: Stage = .none
    @Published private(set) var checking = false
    @Published private(set) var checkFailed = false
    /// Shown in Settings.
    @Published private(set) var lastChecked: Date?

    /// The feed, from the MoteFeed Info.plist key, and https only. A test run
    /// may point MOTE_FEED at another, which may also be http.
    static let feed: URL? = {
        if testFeed, let url = ProcessInfo.processInfo.environment["MOTE_FEED"].flatMap(URL.init(string:)) { return url }
        guard let url = (Bundle.main.infoDictionary?["MoteFeed"] as? String).flatMap(URL.init(string:)), url.scheme == "https"
        else { return nil }
        return url
    }()

    /// The public half of Mote's update key, from the MoteUpdateKey Info.plist key.
    nonisolated static let key: String? = (Bundle.main.infoDictionary?["MoteUpdateKey"] as? String).flatMap {
        UpdateSignature.isKey($0) ? $0 : nil
    }

    static var enabled: Bool { feed != nil && key != nil }
    private static var testFeed: Bool { Storage.testing && ProcessInfo.processInfo.environment["MOTE_FEED"] != nil }

    nonisolated static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }
    /// What updates compare.
    nonisolated static var build: Int { Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0 }

    nonisolated static let installKey = "update.install"
    private static let checkedKey = "update.checked"
    private var installsOnItsOwn: Bool { settings.object(forKey: Self.installKey) as? Bool ?? true }
    private let settings: UserDefaults
    private let enabled: Bool
    private let fetch: () async throws -> AppRelease
    private let installer: @Sendable (AppRelease) async throws -> Void

    /// What the window hears about.
    enum News {
        /// A newer release was detected, before any automatic installation.
        case out(AppRelease)
        /// Installed; it takes over when Mote next opens.
        case ready(AppRelease)
        /// Out, but it couldn't be put in place here: the disk image it is.
        case manual(AppRelease)
    }

    /// Tells the window what happened.
    private var say: ((News) -> Void)?
    private var clock: Timer?
    private var failedAt: Date?
    private var announcedBuild: Int?

    init(
        settings: UserDefaults = Storage.settings, enabled: Bool = Updater.enabled,
        latest: @escaping () async throws -> AppRelease = Updater.latest,
        installer: @escaping @Sendable (AppRelease) async throws -> Void = UpdateInstaller.install
    ) {
        self.settings = settings
        self.enabled = enabled
        self.fetch = latest
        self.installer = installer
        lastChecked = settings.object(forKey: Self.checkedKey) as? Date
        // The previous bundle goes at quit (see UpdateInstaller.sweep).
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { UpdateInstaller.sweep() }
        }
    }

    /// Always checks at launch, then hourly when due; failures retry in five minutes.
    func checkIfDue(then say: @escaping (News) -> Void) {
        self.say = say
        UpdateInstaller.sweep()
        guard enabled else { return }
        if clock == nil {
            clock = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkIfDue() }
            }
            clock?.tolerance = 5 * 60
            check { _ in }
        } else {
            checkIfDue()
        }
    }

    private func checkIfDue() {
        let last = settings.object(forKey: Self.checkedKey) as? Date
        if UpdatePlan.due(last: last, now: Date(), always: Self.testFeed, failed: failedAt) { check { _ in } }
    }

    /// Checks now. A successful result contains the newer release, or nil.
    func check(then done: @escaping (Result<AppRelease?, Error>) -> Void) {
        guard enabled, !checking else { return done(.failure(URLError(.cancelled))) }
        checking = true
        Task {
            do {
                let found = UpdatePlan.newer(try await fetch(), than: Self.build, system: ProcessInfo.processInfo.operatingSystemVersion)
                checking = false
                checkFailed = false
                failedAt = nil
                let now = Date()
                lastChecked = now
                settings.set(now, forKey: Self.checkedKey)
                clock?.fireDate = now.addingTimeInterval(60 * 60)
                clock?.tolerance = 5 * 60
                if let found, announcedBuild != found.build {
                    announcedBuild = found.build
                    say?(.out(found))
                }
                let (next, step) = UpdatePlan.next(after: found, in: stage, installsOnItsOwn: installsOnItsOwn)
                stage = next
                if case .install(let release) = step { install(release) }
                done(.success(found))
            } catch {
                checking = false
                checkFailed = true
                let now = Date()
                failedAt = now
                clock?.fireDate = now.addingTimeInterval(5 * 60)
                clock?.tolerance = 30
                done(.failure(error))
            }
        }
    }

    /// Install, from Settings, for an update that is waiting.
    func install() {
        if case .waiting(let release) = stage { install(release) }
    }

    private func install(_ release: AppRelease) {
        guard UpdatePlan.canInstall(in: stage) else { return }
        stage = .fetching(release)
        let installer = installer
        Task {
            let worked = await Task.detached(priority: .utility) { (try? await installer(release)) != nil }.value
            guard let landed = UpdatePlan.landed(release, worked: worked, in: stage) else { return }
            stage = landed
            say?(worked ? .ready(release) : .manual(release))
        }
    }

    /// Quits and opens again. A shell waits for this process to end before
    /// `open`, which would otherwise just bring the running app forward. Quits
    /// through NSApp so everything saves as with ⌘Q.
    func relaunch() {
        let waiter = Process()
        waiter.executableURL = URL(fileURLWithPath: "/bin/sh")
        let pid = String(ProcessInfo.processInfo.processIdentifier)
        waiter.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; shift; exec \"$@\"", "sh", pid] + Self.reopen
        try? waiter.run()
        NSApp.terminate(nil)
    }

    /// The `open` command. `open` starts with a fresh environment, so a test
    /// run's variables are passed on; a relaunched test run must not see real data.
    private static var reopen: [String] {
        let passed = ["MOTE_PROBE", "MOTE_FEED"].flatMap { key in
            ProcessInfo.processInfo.environment[key].map { ["--env", "\(key)=\($0)"] } ?? []
        }
        return ["/usr/bin/open"] + passed + [Bundle.main.bundleURL.path]
    }

    private static func latest() async throws -> AppRelease {
        guard let feed else { throw URLError(.badURL) }
        let request = URLRequest(url: feed, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true
        else { throw URLError(.badServerResponse) }
        guard let release = AppRelease(appcast: data, feed: feed, allowsHTTP: testFeed)
        else { throw URLError(.cannotParseResponse) }
        return release
    }
}

/// Downloads, checks and swaps in an update, off the main thread. It only
/// ever deletes its scratch folder and the previous bundle.
private nonisolated enum UpdateInstaller {
    enum Refused: Error {
        case noKey, readOnly, download, signature, hash, archive, plist, wrongApp, notNewer, unsigned, wrongTeam, move
    }

    static var running: URL { Bundle.main.bundleURL }
    /// The previous bundle during a swap: beside it, so moving is a rename.
    static var previous: URL { running.deletingLastPathComponent().appending(path: running.lastPathComponent + ".old") }

    static func install(_ release: AppRelease) async throws {
        let files = FileManager.default
        guard let key = Updater.key else { throw Refused.noKey }
        // Not from a disk image, nor from someone else's /Applications.
        guard files.isWritableFile(atPath: running.deletingLastPathComponent().path) else { throw Refused.readOnly }

        // On the same volume, so the final move is a rename.
        let scratch =
            (try? files.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: running, create: true))
            ?? files.temporaryDirectory.appending(path: "mote-update-\(release.build)", directoryHint: .isDirectory)
        try files.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: scratch) }

        let zip = scratch.appending(path: "Mote.zip")
        try await download(release.archive, to: zip)
        // Signed with Mote's update key, or not installed at all.
        guard let signature = release.signature, let bytes = try? Data(contentsOf: zip, options: .mappedIfSafe),
            UpdateSignature.verify(bytes, signature: signature, key: key)
        else { throw Refused.signature }
        if let expected = release.sha256, try sha256(of: zip) != expected { throw Refused.hash }
        let unpacked = scratch.appending(path: "unpacked", directoryHint: .isDirectory)
        try unzip(zip, into: unpacked)
        guard
            let fresh = try files.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil).first(where: {
                $0.pathExtension == "app"
            })
        else { throw Refused.archive }
        try check(fresh, team: team(of: running))
        try swap(in: fresh)
    }

    private static func download(_ url: URL, to file: URL) async throws {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        let (downloaded, response) = try await URLSession.shared.download(for: request)
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { throw Refused.download }
        // URLSession deletes its file once this returns.
        try FileManager.default.moveItem(at: downloaded, to: file)
    }

    private static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        return try UpdatePlan.sha256 { try handle.read(upToCount: 1 << 20) }
    }

    /// With ditto, which keeps permissions. Mote doesn't turn on
    /// LSFileQuarantineEnabled, so the download isn't quarantined: `check`
    /// is what vets it, not Gatekeeper.
    private static func unzip(_ zip: URL, into folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, folder.path]
        ditto.standardOutput = FileHandle.nullDevice
        ditto.standardError = FileHandle.nullDevice
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw Refused.archive }
    }

    /// The same bundle id, a higher build, and code whose signature is whole.
    /// A copy signed with a Developer ID also wants the new one from the same
    /// team, as an extra check on top of the update key.
    private static func check(_ bundle: URL, team: String?) throws {
        guard let data = try? Data(contentsOf: bundle.appending(path: "Contents/Info.plist")),
            let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw Refused.plist }
        guard let identifier = Bundle.main.bundleIdentifier, info["CFBundleIdentifier"] as? String == identifier else {
            throw Refused.wrongApp
        }
        guard Int(info["CFBundleVersion"] as? String ?? "") ?? 0 > Updater.build else { throw Refused.notNewer }

        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code else { throw Refused.unsigned }
        var requirement: SecRequirement?
        if let team {
            guard
                SecRequirementCreateWithString(UpdatePlan.requirement(team: team, identifier: identifier) as CFString, [], &requirement)
                    == errSecSuccess
            else { throw Refused.unsigned }
        }
        let strict = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(code, strict, requirement) == errSecSuccess else { throw Refused.unsigned }
        if let team, self.team(of: bundle) != team { throw Refused.wrongTeam }
    }

    /// The signing team, or nil for ad-hoc and unsigned bundles.
    private static func team(of bundle: URL) -> String? {
        var code: SecStaticCode?
        var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code,
            SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Moves this bundle aside and the new one in, putting it back if that
    /// fails. The running app carries on from the moved bundle, keeping its
    /// identity and keychain access until it quits.
    private static func swap(in fresh: URL) throws {
        let files = FileManager.default
        sweep()
        guard !files.fileExists(atPath: previous.path) else { throw Refused.move }
        try files.moveItem(at: running, to: previous)
        do {
            try files.moveItem(at: fresh, to: running)
        } catch {
            try? files.moveItem(at: previous, to: running)
            throw Refused.move
        }
    }

    /// Deletes the previous bundle, if it is this app's. At quit, and at launch
    /// in case the last quit wasn't clean.
    static func sweep() {
        guard let data = try? Data(contentsOf: previous.appending(path: "Contents/Info.plist")),
            let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier
        else { return }
        try? FileManager.default.removeItem(at: previous)
    }
}
