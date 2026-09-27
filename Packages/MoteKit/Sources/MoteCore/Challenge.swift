import Foundation

/// What to do when a page's certificate or sign-in is asked for.
public enum Challenge {
    /// What happens to an HTTPS connection whose certificate was checked.
    public enum Trust: Equatable, Sendable {
        /// Let WebKit decide: the certificate is good, or it's a part of the
        /// page that fails quietly.
        case usual
        /// Accepted without asking.
        case accept
        /// Ask the person first.
        case ask
    }

    /// A good certificate goes ahead. A bad one is accepted on this Mac's own
    /// addresses and on hosts the person already let through; otherwise they
    /// are asked, but only for the page itself (`pageHost`), never its parts.
    public static func trust(valid: Bool, host: String, excused: Set<String>, pageHost: String?) -> Trust {
        if valid { return .usual }
        let host = host.lowercased()
        if isLoopback(host) || excused.contains(host) { return .accept }
        return pageHost?.lowercased() == host ? .ask : .usual
    }

    /// Whether `host` can only be this Mac: `localhost`, `::1`, or a written
    /// 127.x.x.x address (`127.0.0.1.example.com` is not).
    public static func isLoopback(_ host: String) -> Bool {
        if ["localhost", "::1", "[::1]"].contains(host) { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil } && parts[0] == "127"
    }

    /// A sign-in is offered twice, then given up.
    public static func mayAskToSignIn(failures: Int) -> Bool { failures < 2 }

    /// The heading of a page's alert, confirm or prompt: the site asking, so a
    /// page can't pass for Mote or the system.
    public static func dialogTitle(host: String) -> String {
        host.isEmpty ? "This page says" : host
    }
}
