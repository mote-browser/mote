import Foundation

/// Decides what happens to a navigation, from plain facts about it, so the
/// rules can be tested without WebKit.
public enum NavigationPolicy {
    /// Schemes the browser loads itself. chrome-extension and
    /// webkit-extension are extension pages, which WebKit serves.
    public static let loadable: Set<String> = [
        "http", "https", "file", "about", "data", "blob", "chrome-extension", "webkit-extension",
    ]

    /// Modifier keys held during a click.
    public struct Keys: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let shift = Keys(rawValue: 1 << 0)
        public static let command = Keys(rawValue: 1 << 1)
        public static let option = Keys(rawValue: 1 << 2)
        public static let control = Keys(rawValue: 1 << 3)
    }

    /// A link click or other navigation, as WebKit reports it.
    public struct Request: Sendable {
        public var scheme: String
        public var clicked: Bool
        /// WebKit's button mask: 1 left, 2 right, 4 middle.
        public var button: Int
        public var keys: Keys
        /// Shift-click previews are on and this tab can show one.
        public var canPeek: Bool

        public init(scheme: String, clicked: Bool, button: Int = 1, keys: Keys = [], canPeek: Bool = false) {
            self.scheme = scheme.lowercased()
            self.clicked = clicked
            self.button = button
            self.keys = keys
            self.canPeek = canPeek
        }

        var isWeb: Bool { scheme == "http" || scheme == "https" }
    }

    public enum Decision: Equatable, Sendable {
        case load
        /// Already handled elsewhere (a middle-click opens its own tab).
        case ignore
        /// Show a link preview over the page.
        case peek
        case openTab(foreground: Bool)
        /// Hand the URL to the app that owns its scheme.
        case handOff
    }

    public static func decide(_ request: Request) -> Decision {
        // Middle-clicks are opened by the page script, which sees them first.
        if request.clicked, request.button == 4 { return .ignore }
        if request.clicked, request.isWeb {
            // Shift alone previews; ⌘ opens a background tab, ⌘⇧ a foreground one.
            if request.canPeek, request.keys == .shift { return .peek }
            if request.keys.contains(.command) { return .openTab(foreground: request.keys.contains(.shift)) }
        }
        return loadable.contains(request.scheme) ? .load : .handOff
    }

    /// Whether a URL for another app may be opened: from the main frame, or
    /// from a click in a frame, so ads in frames can't launch apps.
    public static func mayHandOff(mainFrame: Bool, clicked: Bool) -> Bool {
        mainFrame || clicked
    }

    /// Clicked mail and phone links open their app without asking.
    public static func handsOffQuietly(scheme: String, clicked: Bool) -> Bool {
        clicked && ["mailto", "tel"].contains(scheme.lowercased())
    }

    /// Whether a response is shown or downloaded.
    ///
    /// Redirects are always followed, even with a binary Content-Type (as
    /// some servers send), and "Content-Disposition: attachment" always
    /// downloads, even a type WebKit could show.
    public static func downloads(status: Int?, disposition: String?, canShow: Bool) -> Bool {
        if let status, (300...399).contains(status) { return false }
        if let disposition, disposition.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("attachment") {
            return true
        }
        return !canShow
    }
}

/// A page that failed to load: what went wrong, where, and what to say.
public struct LoadFailure: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case certificate, noHost, offline, timedOut, refused, other
    }

    public var kind: Kind
    /// The address that failed, when WebKit says.
    public var url: URL?

    public init(kind: Kind, url: URL?) {
        self.kind = kind
        self.url = url
    }

    /// The failure for a load error, or nil when it isn't one worth showing:
    /// cancellations (redirects, stopped loads) and WebKit's "frame load
    /// interrupted", which ends a navigation that became a download.
    public init?(domain: String, code: Int, url: URL?) {
        if code == NSURLErrorCancelled { return nil }
        if domain == "WebKitErrorDomain", code == 102 { return nil }
        self.init(kind: Self.kind(code), url: url)
    }

    static func kind(_ code: Int) -> Kind {
        switch code {
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return .noHost
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return .offline
        case NSURLErrorTimedOut:
            return .timedOut
        case NSURLErrorCannotConnectToHost:
            return .refused
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate,
            NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
            NSURLErrorServerCertificateNotYetValid, NSURLErrorClientCertificateRejected:
            return .certificate
        default:
            return .other
        }
    }

    /// The failing host, lowercased.
    public var host: String? {
        guard let host = url?.host(), !host.isEmpty else { return nil }
        return host.lowercased()
    }

    public var title: String {
        switch kind {
        case .certificate: "This connection isn't private"
        case .noHost: "No site at that address"
        case .offline: "You're offline"
        case .timedOut: "The site took too long"
        case .refused: "The site refused to connect"
        case .other: "The page didn't load"
        }
    }

    public var detail: String {
        switch kind {
        case .certificate:
            "The site's certificate can't be trusted, so it may not be who it says it is. Someone could read or change what you send."
        case .noHost:
            "Check the address for typos. The site may have moved or no longer exist."
        case .offline:
            "Mote can't reach the internet. Check your Wi-Fi or network, then try again."
        case .timedOut:
            "The site didn't answer in time. It may be busy or down for a moment."
        case .refused:
            "The site is there but isn't accepting connections right now."
        case .other:
            "Something went wrong while loading this page."
        }
    }

    /// Whether the person may go ahead anyway: a bad certificate, on a known host.
    public var canContinue: Bool { kind == .certificate && host != nil }
}
