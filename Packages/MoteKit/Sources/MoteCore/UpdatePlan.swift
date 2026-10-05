import CryptoKit
import Foundation

/// Where an update stands, and what to do as news comes in. The downloading
/// and swapping are the app's; the decisions are here.
public enum UpdatePlan {
    public enum Stage: Equatable, Sendable {
        /// Nothing newer.
        case none
        /// Downloading and checking it.
        case fetching(AppRelease)
        /// Installed; it opens next launch.
        case ready(AppRelease)
        /// Installing in place failed; the disk image is offered instead.
        case offered(AppRelease)
        /// Out, and waiting because installing on its own is off.
        case waiting(AppRelease)
    }

    public enum Step: Equatable, Sendable {
        case nothing
        case install(AppRelease)
        /// Wait for the user, and say so.
        case wait(AppRelease)
    }

    /// Check at launch, after 20 hours since success, or five minutes after failure.
    public static func due(last: Date?, now: Date, always: Bool, failed: Date? = nil) -> Bool {
        if always { return true }
        if let failed { return now.timeIntervalSince(failed) >= 5 * 60 }
        return now.timeIntervalSince(last ?? .distantPast) > 20 * 60 * 60
    }

    /// Whether a release from the feed is worth anything to this app.
    public static func newer(_ release: AppRelease?, than build: Int, system: OperatingSystemVersion) -> AppRelease? {
        guard let release, release.build > build, release.runs(on: system) else { return nil }
        return release
    }

    /// What to do with what the feed said. Nothing newer leaves an installed
    /// update ready; something newer installs, or waits and says so once.
    public static func next(after found: AppRelease?, in stage: Stage, installsOnItsOwn: Bool) -> (Stage, Step) {
        guard let found else {
            if case .ready = stage { return (stage, .nothing) }
            return (.none, .nothing)
        }
        if installsOnItsOwn { return (stage, canInstall(in: stage) ? .install(found) : .nothing) }
        switch stage {
        case .fetching, .ready: return (stage, .nothing)
        case .waiting(let known) where known == found: return (stage, .nothing)
        case .none, .offered, .waiting: return (.waiting(found), .wait(found))
        }
    }

    /// One install at a time, and none once one is in: a second swap in the
    /// same run would move the bundle the app is running from.
    public static func canInstall(in stage: Stage) -> Bool {
        switch stage {
        case .fetching, .ready: false
        case .none, .offered, .waiting: true
        }
    }

    /// Where an install ended up, if it is still the one being fetched.
    public static func landed(_ release: AppRelease, worked: Bool, in stage: Stage) -> Stage? {
        guard case .fetching(let fetching) = stage, fetching == release else { return nil }
        return worked ? .ready(release) : .offered(release)
    }

    /// The code requirement an update must meet, as `codesign -d -r-` prints
    /// it: Apple's anchor, the Developer ID intermediate (…6.2.6) and
    /// application leaf (…6.1.13), this team and this bundle id. A Team ID
    /// alone proves nothing: any self-made certificate can claim one.
    public static func requirement(team: String, identifier: String) -> String {
        "anchor apple generic and identifier \"\(identifier)\""
            + " and certificate 1[field.1.2.840.113635.100.6.2.6]"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13]"
            + " and certificate leaf[subject.OU] = \"\(team)\""
    }

    /// The SHA-256 of what `read` hands over chunk by chunk, in lowercase hex.
    public static func sha256(_ read: () throws -> Data?) rethrows -> String {
        var hash = SHA256()
        while let chunk = try read(), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
