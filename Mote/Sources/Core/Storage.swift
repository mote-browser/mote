import Foundation
import WebKit

/// Where Mote keeps things. A test run (a Debug build, or MOTE_PROBE set)
/// lives in a world of its own and never touches the real folder, settings
/// or WebKit stores.
enum Storage {
    /// Debug builds are always a test run, so real data never depends on
    /// remembering a flag.
    nonisolated static var testing: Bool {
        #if DEBUG
        true
        #else
        ProcessInfo.processInfo.environment["MOTE_PROBE"] != nil
        #endif
    }

    /// The test world's name: "test", or MOTE_PROBE's value cleaned up, so
    /// test sessions side by side don't share anything. Nil for the real one.
    static let world: String? = {
        guard testing else { return nil }
        let asked = (ProcessInfo.processInfo.environment["MOTE_PROBE"] ?? "").lowercased()
            .filter { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" }
        return ["", "1", "test"].contains(asked) ? "test" : asked
    }()

    /// A test run for measuring (MOTE_MEASURE too), which keeps the release
    /// build's background throttling and App Nap.
    static var measuring: Bool { testing && ProcessInfo.processInfo.environment["MOTE_MEASURE"] != nil }

    /// The profile folder in Application Support.
    static let folder = URL.applicationSupportDirectory.appending(path: world.map { "Mote (\($0))" } ?? "Mote", directoryHint: .isDirectory)

    static func file(_ name: String) -> URL { folder.appending(path: name) }

    /// Sets aside a file that no longer reads, so the next save doesn't
    /// overwrite it. If that fails, nothing more is done: the read already
    /// came back empty.
    static func quarantine(_ file: URL) {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let aside = file.deletingLastPathComponent()
            .appending(path: "\(file.deletingPathExtension().lastPathComponent).unreadable-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: file, to: aside)
    }

    /// The settings: the standard defaults, or the test world's own suite.
    static let settings: UserDefaults = {
        guard let world else { return .standard }
        return UserDefaults(suiteName: "io.github.mote-browser.mote.test" + (world == "test" ? "" : ".\(world)")) ?? .standard
    }()

    // MARK: - WebKit

    /// The website data store. WebKit's default one belongs to the bundle, not
    /// the folder, so a test world uses one with a fixed identifier instead,
    /// and never shares cookies or sign-ins with the real browser.
    static var websites: WKWebsiteDataStore {
        guard testing, !ownContainer else { return .default() }
        return WKWebsiteDataStore(forIdentifier: probeStore(1))
    }

    /// Running under another bundle id, which has its own WebKit container
    /// and can use the default stores (they keep extension workers alive
    /// differently from identified ones).
    static var ownContainer: Bool { Bundle.main.bundleIdentifier != "io.github.mote-browser.mote" }

    /// A test world's fixed store identifier (kind 1 for websites, 2 for
    /// extensions): 5E4C0000-0000-4000-8000-00000000000k for "test", which
    /// `make fresh` wipes, and for named worlds a 32-bit FNV-1a hash of the
    /// name in the second and third groups.
    static func probeStore(_ kind: UInt32) -> UUID {
        let hash: UInt32 =
            world.flatMap { $0 == "test" ? nil : $0 }.map { name in
                name.utf8.reduce(2_166_136_261) { ($0 ^ UInt32($1)) &* 16_777_619 }
            } ?? 0
        return UUID(uuidString: String(format: "5E4C%04X-%04X-4000-8000-%012X", hash >> 16, hash & 0xFFFF, kind))!
    }
}
