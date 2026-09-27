import MoteCore
import WebKit

/// Sign-in forms, focus and full screen, as the page's forms script reports
/// them, for offering to save and fill passwords.
///
/// Filling goes through the native value setter and fires input and change
/// events; setting `.value` directly goes unseen by frameworks like React.
final class FormRelay: NSObject, WKScriptMessageHandler {
    static let name = "moteForms"
    /// Reports sign-in forms, what they send, focus and full screen, and gives
    /// Mote `window.__moteForms` (`fill`, `hasPassword`, `unsaved`) in its own
    /// world. See Scripts/src/forms.ts.
    static let script = InjectedScript.source("forms")

    /// Hides `PublicKeyCredential` but keeps `navigator.credentials`, which
    /// sites also use for stored passwords. When an extension (1Password, say)
    /// installs its own `get`/`create` or reaches the object from its script,
    /// it comes back so sites find the extension; public-key requests left to
    /// the browser fail at once with `NotAllowedError`.
    /// See Scripts/src/passkeys-hidden.ts.
    static let withoutPasskeys = InjectedScript.source("passkeys-hidden")

    /// Whether sites are offered passkeys (Settings › Passwords).
    ///
    /// Without Apple's browser entitlement WebKit has no platform
    /// authenticator but still shows sites `PublicKeyCredential`, so they
    /// start passkey sign-ins that can't finish; hiding it sends them to
    /// passwords. Entitled builds turn this on and answer in Passkeys.swift.
    static var passkeysOffered: Bool {
        get { Storage.settings.bool(forKey: "passkeys") }
        set { Storage.settings.set(newValue, forKey: "passkeys") }
    }

    weak var tab: Tab? {
        didSet { watchFullscreen() }
    }

    private var fullscreen: NSKeyValueObservation?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let event = FormEvent(message.body) else { return }
        MainActor.assumeIsolated {
            guard let tab else { return }
            switch event {
            case .sent(let user, let password): tab.sentSignIn(user: user, password: password)
            case .settled: tab.settleSignIn(navigated: false)
            case .focus(let typing, let field):
                tab.typing = typing
                tab.fieldFocused(field)
            // The page's word comes after the web view's (see watchFullscreen).
            case .fullscreen(let on): tab.immersed = on
            }
        }
    }

    /// Full screen, known before it happens.
    ///
    /// WebKit moves the page to a window of its own and slides ours away; for
    /// a frame or two ours still shows, and everything Mote draws is white,
    /// which leaves a pale band across the animation. A moment's notice is
    /// enough to paint it black. The page's own `requestFullscreen` is out of
    /// sight of Mote's world and its `fullscreenchange` comes late, so the web
    /// view's state is watched: it turns to entering first.
    private func watchFullscreen() {
        fullscreen = tab?.built?.observe(\.fullscreenState, options: [.new]) { [weak self] web, _ in
            MainActor.assumeIsolated {
                if let on = FormRelay.immersed(web.fullscreenState) { self?.tab?.immersed = on }
            }
        }
    }

    /// Whether a view in `state` counts as full screen; nil while it is
    /// leaving, which keeps the last answer until it is out.
    static func immersed(_ state: WKWebView.FullscreenState) -> Bool? {
        switch state {
        case .enteringFullscreen, .inFullscreen: true
        case .notInFullscreen: false
        default: nil
        }
    }
}
