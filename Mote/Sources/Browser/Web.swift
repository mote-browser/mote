import MoteCore
import WebKit

/// How Mote's web views are set up: their configuration, the content world
/// its own scripts run in, and the user agent.
enum Web {
    /// The isolated world for Mote's page scripts and message handlers. Out of
    /// the page's world, `window.webkit` stays hidden; sites use it to spot
    /// embedded web views (Google answers with CAPTCHAs and blocks sign-ins).
    /// Only the passkey patch runs in the page's world.
    @MainActor static let world = WKContentWorld.world(name: "Mote")

    /// Every page view alive, for the bench.
    @MainActor static let pages = NSHashTable<PageView>.weakObjects()

    /// Mote's message handler names, in the worlds they are registered in.
    @MainActor private static var handlers: [(String, WKContentWorld)] {
        [
            ScrollRelay.name, ElementHiderRelay.name, FormRelay.name, ImageRelay.name, WebStoreBridge.name, PasskeyRelay.name,
            MiddleRelay.name,
        ]
        .flatMap { [($0, world), ($0, .page)] } + [(HoveredLink.name, .defaultClient)]
    }

    /// Removes Mote's message handlers from a controller. A tab opened by a
    /// link starts from its opener's configuration, and registering a name
    /// twice crashes.
    @MainActor static func release(_ controller: WKUserContentController) {
        for (name, world) in handlers { controller.removeScriptMessageHandler(forName: name, contentWorld: world) }
    }

    /// Appended to the user agent after "(KHTML, like Gecko)", for tabs and
    /// extension views. It carries the installed Safari's version because that
    /// matches the system WebKit; a fixed one drifts with every macOS and makes
    /// sites send code the engine can't run.
    static let userAgentName = SafariVersion.userAgentName(version: installedSafari)

    private static var installedSafari: String {
        let bundles = ["/System/Cryptexes/App/System/Applications/Safari.app", "/Applications/Safari.app"]
        return bundles.lazy.compactMap { Bundle(path: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String }.first
            ?? SafariVersion.shipped(withMacOS: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }

    /// A tab's configuration. Sign-ins persist across launches in the space's
    /// store; a private tab gets a store that keeps nothing, or `store`, its
    /// private opener's, so a followed link keeps that page's session.
    /// `space` is the tab's space when it isn't the current one.
    static func configuration(shy: Bool = false, space: UUID? = nil, store: WKWebsiteDataStore? = nil) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore =
            store ?? (shy ? .nonPersistent() : MainActor.assumeIsolated { Spaces.store(for: space ?? Spaces.current) })
        // Extensions reach private tabs only when Settings › Extensions allows it,
        // and the controller has to be in place before the view exists.
        if #available(macOS 15.4, *), !shy || Storage.settings.bool(forKey: "extensions.private") {
            MainActor.assumeIsolated { Extensions.attach(config) }
        }
        // Without it the user agent names no browser and Google serves its old page.
        config.applicationNameForUserAgent = userAgentName
        config.allowsAirPlayForMediaPlayback = true
        // Off by default on macOS, which makes video fullscreen buttons do nothing.
        config.preferences.isElementFullscreenEnabled = true
        // `window.open` only from a click, as Safari blocks pop-ups.
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.mediaTypesRequiringUserActionForPlayback = .audio
        if Storage.testing, !Storage.measuring { config.preferences.inactiveSchedulingPolicy = .none }
        inspector(config.preferences)
        return config
    }

    /// WebKit's developer extras: Inspect Element and the Web Inspector (see
    /// Inspector.swift). `isInspectable` alone only lists the page in Safari's
    /// Develop menu. The setter is private, so it is looked up first.
    static func inspector(_ preferences: WKPreferences, on: Bool = true) {
        let set = NSSelectorFromString("_setDeveloperExtrasEnabled:")
        guard preferences.responds(to: set) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(preferences.method(for: set), to: Setter.self)(preferences, set, on)
    }
}
