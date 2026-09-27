import AuthenticationServices
import MoteCore
import OSLog
import WebKit

/// Passkeys and security keys, asked for by pages and answered by Mote
/// rather than WebKit.
///
/// WebKit's own way keeps an AutoFill operation open with
/// AuthenticationServicesAgent while a page waits (conditional mediation).
/// If the app quits meanwhile, the agent keeps it and refuses every later
/// request ("Request already in progress", AuthorizationError 1) until it
/// restarts. So Mote runs the ceremony itself, as Chrome and Firefox do: the
/// request is checked against the frame WebKit names (see WebAuthn) and
/// handed to AuthenticationServices' browser API with client data made here.
/// The origin always comes from WebKit, never from the page.
///
/// Conditional mediation isn't offered: pages hear it is unavailable unless a
/// password manager extension provides it, and conditional requests left to
/// Mote wait until aborted and never reach macOS.
@MainActor
final class Passkeys: NSObject {
    static let shared = Passkeys()

    private static let log = Logger(subsystem: "io.github.mote-browser.mote", category: "Passkeys")

    /// Requests seen and the last one checked, for the bench.
    private(set) static var asked = 0
    private(set) static var last: [String: Any] = [:]

    /// Test runs only: rehearsals wait for `releaseRehearsal()` rather than
    /// answering at once, so tests can see a request running.
    static var rehearsalWaits = false

    /// CFNetwork's private public-suffix check, the one WebKit uses. Without
    /// it only a page's exact host can be a relying party.
    nonisolated static let publicSuffix: (@convention(c) (CFString) -> Bool)? = {
        guard let symbol = dlsym(dlopen("/System/Library/Frameworks/CFNetwork.framework/CFNetwork", RTLD_NOW), "_CFHostIsDomainTopLevel")
        else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (CFString) -> Bool).self)
    }()

    private static var isPublicSuffix: ((String) -> Bool)? {
        publicSuffix.map { test in { test($0 as CFString) } }
    }

    // MARK: - Asking macOS

    /// Whether macOS lets this browser use the Mac's passkeys. Asked once;
    /// the answer lives in System Settings › Privacy & Security.
    static var access: ASAuthorizationWebBrowserPublicKeyCredentialManager.AuthorizationState {
        ASAuthorizationWebBrowserPublicKeyCredentialManager().authorizationStateForPlatformCredentials
    }

    /// Callers waiting for that one question to be answered.
    private static var awaiting: [() -> Void]?

    /// Asks the first time, then runs `then`.
    private static func authorize(then: @escaping () -> Void) {
        guard Preferences.entitledToPasskeys, access == .notDetermined else { return then() }
        guard awaiting == nil else { return awaiting?.append(then) ?? () }
        awaiting = [then]
        ASAuthorizationWebBrowserPublicKeyCredentialManager().requestAuthorizationForPublicKeyCredentials { _ in
            Task { @MainActor in
                let everyone = awaiting ?? []
                awaiting = nil
                everyone.forEach { $0() }
            }
        }
    }

    // MARK: - The request running

    /// The document that asked: its web view, and the name the bridge in that
    /// document's frame drew at random for itself. The page can neither read
    /// nor set it: the bridge lives in Mote's world and adds it to every message.
    struct Asker: Equatable {
        let view: ObjectIdentifier
        let document: String
    }

    /// Who is asking, as WebKit tells it.
    struct Caller {
        let origin: WKSecurityOrigin
        let mainFrame: Bool
        /// The host of the page holding the frame.
        let pageHost: String?
        let window: NSWindow?
        /// Nil when WebKit names no web view or the bridge no document.
        let asker: Asker?
    }

    /// macOS shows one sheet at a time, so one request runs. Only the
    /// document that made it can cancel it or, as in Safari, replace it with
    /// a new one; any other document asking meanwhile is refused.
    private struct Running {
        let serial: Int
        let asker: Asker
        let token: String
        let answer: ([String: Any]) -> Void
        var controller: ASAuthorizationController?
        /// A test run's made-up credential, held while `rehearsalWaits`.
        var rehearsal: [String: Any]?
    }

    private var running: Running?
    private var serials = 0
    private weak var anchor: NSWindow?

    var isWaiting: Bool { running != nil }

    func releaseRehearsal() {
        if let reply = running?.rehearsal { finish(reply) }
    }

    /// The page let its request go. Only the document that asked can.
    func cancel(token: String?, from asker: Asker?) {
        guard let current = running, let token, current.token == token, current.asker == asker else { return }
        running = nil
        current.controller?.cancel()
        current.answer(WebAuthn.failure("AbortError"))
    }

    func perform(_ body: [String: Any], from caller: Caller, answer: @escaping ([String: Any]) -> Void) {
        let origin = caller.origin
        let who = WebAuthn.Caller(
            scheme: origin.protocol, host: origin.host, port: origin.port, mainFrame: caller.mainFrame, pageHost: caller.pageHost,
            // Test runs are never the frontmost app.
            focused: Storage.testing || (NSApp.isActive && caller.window?.isKeyWindow == true), known: caller.asker != nil)
        let token = body["token"] as? String
        // Turned off in Settings, requests can still come through an extension's
        // page script; they're refused as a browser without passkeys would.
        if let refusal = WebAuthn.check(who, offered: FormRelay.passkeysOffered, token: token) { return refuse(answer, refusal) }
        guard let asker = caller.asker, let token else { return }

        let request: WebAuthn.Request
        switch WebAuthn.read(body, host: who.host, isPublicSuffix: Self.isPublicSuffix) {
        case .success(let read): request = read
        case .failure(let refusal): return refuse(answer, refusal)
        }
        let clientData = ASPublicKeyCredentialClientData(challenge: request.challenge, origin: who.origin)
        let asks = ASRequests.make(for: request, clientData: clientData)
        guard !asks.isEmpty else { return refuse(answer, .init("NotSupportedError", "no authenticator makes that kind of key")) }

        if let current = running {
            guard current.asker == asker else {
                return refuse(answer, .init("NotAllowedError", "another document's request is running"))
            }
            // As in Safari, the document's new request takes its old one's place.
            running = nil
            current.controller?.cancel()
            current.answer(WebAuthn.failure("NotAllowedError"))
        }

        Self.asked += 1
        Self.last = ["kind": request.name, "rp": request.rp, "origin": who.origin, "requests": asks.count]
        Self.log.notice("\(request.name, privacy: .public) for \(request.rp, privacy: .public) from \(who.origin, privacy: .public)")
        serials += 1
        let serial = serials

        // Test runs never show the sheet: a made-up credential still takes the
        // request through every check and the page script.
        if Storage.testing {
            let reply = WebAuthn.rehearsal(request, origin: who.origin)
            guard Self.rehearsalWaits else { return answer(reply) }
            running = Running(serial: serial, asker: asker, token: token, answer: answer, rehearsal: reply)
            return
        }

        running = Running(serial: serial, asker: asker, token: token, answer: answer)
        Self.authorize { [weak self] in
            // Not if the page let it go, or replaced it, meanwhile.
            guard let self, running?.serial == serial else { return }
            let controller = ASAuthorizationController(authorizationRequests: asks)
            controller.delegate = self
            controller.presentationContextProvider = self
            running?.controller = controller
            anchor = caller.window
            controller.performRequests()
        }
    }

    private func finish(_ reply: [String: Any]) {
        let current = running
        running = nil
        current?.answer(reply)
    }

    /// The reason goes to the log, never to the page.
    private func refuse(_ answer: ([String: Any]) -> Void, _ refusal: WebAuthn.Refusal) {
        Self.log.notice("refused: \(refusal.reason, privacy: .public)")
        answer(WebAuthn.failure(refusal.name))
    }
}

extension Passkeys: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        anchor ?? NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard controller === running?.controller else { return }
        let credential = authorization.credential
        if let signed = credential as? ASAuthorizationPublicKeyCredentialAssertion {
            let platform = (credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion)?.attachment == .platform
            Self.log.notice("signed in")
            finish(
                WebAuthn.assertion(
                    id: signed.credentialID, clientData: signed.rawClientDataJSON, authenticatorData: signed.rawAuthenticatorData,
                    signature: signed.signature, user: signed.userID, attachment: platform ? "platform" : "cross-platform"))
        } else if let made = credential as? ASAuthorizationPublicKeyCredentialRegistration {
            let platform = credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration
            Self.log.notice("made one")
            finish(
                WebAuthn.registration(
                    id: made.credentialID, clientData: made.rawClientDataJSON, attestation: made.rawAttestationObject ?? Data(),
                    transports: platform == nil ? ["usb"] : ["hybrid", "internal"],
                    attachment: platform?.attachment == .platform ? "platform" : "cross-platform"))
        } else {
            finish(WebAuthn.failure("NotAllowedError"))
        }
    }

    /// Only "already made" is told apart; every other failure reads as
    /// NotAllowedError, so sites can't tell them apart.
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        guard controller === running?.controller else { return }
        Self.log.notice("failed: \(String(describing: error), privacy: .public)")
        let error = error as NSError
        let exists = error.domain == ASAuthorizationError.errorDomain && error.code == 1006
        finish(WebAuthn.failure(exists ? "InvalidStateError" : "NotAllowedError"))
    }
}

/// AuthenticationServices requests for a checked WebAuthn request: the
/// Mac's own passkeys and, from macOS 14.4, security keys.
private enum ASRequests {
    static func make(for request: WebAuthn.Request, clientData: ASPublicKeyCredentialClientData) -> [ASAuthorizationRequest] {
        let verification = verification(request.verification)
        let platform = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: request.rp)
        var asks: [ASAuthorizationRequest] = []
        switch request.kind {
        case .get(let allowed):
            let signIn = platform.createCredentialAssertionRequest(clientData: clientData)
            signIn.allowedCredentials = allowed.map { ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0.id) }
            signIn.userVerificationPreference = verification
            asks.append(signIn)
            if #available(macOS 14.4, *) {
                let key = ASAuthorizationSecurityKeyPublicKeyCredentialProvider(relyingPartyIdentifier: request.rp)
                    .createCredentialAssertionRequest(clientData: clientData)
                key.allowedCredentials = allowed.map(securityKey)
                key.userVerificationPreference = verification
                asks.append(key)
            }
        case .create(let creation):
            let user = creation.user
            let attestation = attestation(creation.attestation)
            if creation.allowsPlatform {
                let made = platform.createCredentialRegistrationRequest(clientData: clientData, name: user.name, userID: user.id)
                made.displayName = user.displayName
                made.userVerificationPreference = verification
                made.attestationPreference = attestation
                if #available(macOS 14.4, *) {
                    made.excludedCredentials = creation.excluded.map {
                        ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0.id)
                    }
                }
                asks.append(made)
            }
            if creation.allowsSecurityKey, #available(macOS 14.4, *) {
                let key = ASAuthorizationSecurityKeyPublicKeyCredentialProvider(relyingPartyIdentifier: request.rp)
                    .createCredentialRegistrationRequest(
                        clientData: clientData, displayName: user.displayName, name: user.name, userID: user.id)
                key.credentialParameters = creation.algorithms.map {
                    ASAuthorizationPublicKeyCredentialParameters(algorithm: ASCOSEAlgorithmIdentifier(rawValue: $0))
                }
                key.userVerificationPreference = verification
                key.attestationPreference = attestation
                key.residentKeyPreference = residentKey(creation.residentKey)
                key.excludedCredentials = creation.excluded.map(securityKey)
                asks.append(key)
            }
        }
        return asks
    }

    private static func securityKey(_ descriptor: WebAuthn.Descriptor) -> ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor {
        let named: [ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor.Transport] = descriptor.transports.compactMap {
            switch $0 {
            case "usb": .usb
            case "nfc": .nfc
            case "ble": .bluetooth
            default: nil
            }
        }
        return .init(
            credentialID: descriptor.id,
            transports: named.isEmpty ? ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor.Transport.allSupported : named)
    }

    private static func verification(_ value: String) -> ASAuthorizationPublicKeyCredentialUserVerificationPreference {
        switch value {
        case "required": .required
        case "discouraged": .discouraged
        default: .preferred
        }
    }

    private static func attestation(_ value: String) -> ASAuthorizationPublicKeyCredentialAttestationKind {
        switch value {
        case "direct": .direct
        case "indirect": .indirect
        case "enterprise": .enterprise
        default: .none
        }
    }

    private static func residentKey(_ value: String) -> ASAuthorizationPublicKeyCredentialResidentKeyPreference {
        switch value {
        case "required": .required
        case "preferred": .preferred
        default: .discouraged
        }
    }
}

/// Takes WebAuthn requests from pages and sends back the answers.
final class PasskeyRelay: NSObject, WKScriptMessageHandlerWithReply {
    static let name = "motePasskeys"
    /// The window events between the page script and `bridge`, named at random
    /// once per launch: a page can't listen for, forge or spot events it
    /// can't name. Both scripts get them from here, as config.
    nonisolated static let asked = randomName()
    nonisolated static let answered = randomName()
    /// How a second copy of the relay in a page's world (an extension's and
    /// Mote's) learns the first is already in.
    nonisolated static let installed = randomName()

    /// 128 bits from the system's secure generator, as hex.
    nonisolated static func randomName() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<16).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }.joined()
    }

    func userContentController(
        _ controller: WKUserContentController, didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        MainActor.assumeIsolated {
            guard let body = message.body as? [String: Any] else { return replyHandler(nil, "Not a request") }
            // The web view WebKit names, and the document the bridge names in it.
            let asker = message.webView.flatMap { view in
                (body["document"] as? String).flatMap { $0.isEmpty ? nil : Passkeys.Asker(view: ObjectIdentifier(view), document: $0) }
            }
            if body["kind"] as? String == "cancel" {
                Passkeys.shared.cancel(token: body["token"] as? String, from: asker)
                return replyHandler(true, nil)
            }
            let caller = Passkeys.Caller(
                origin: message.frameInfo.securityOrigin, mainFrame: message.frameInfo.isMainFrame,
                pageHost: message.webView?.url?.host(), window: message.webView?.window, asker: asker)
            Passkeys.shared.perform(body, from: caller) { replyHandler($0, nil) }
        }
    }

    /// Goes into the page's world at document start. It replaces `get` and
    /// `create` for public-key requests and passes others to WebKit, patching
    /// the prototype since WebKit remakes `navigator.credentials` when nothing
    /// holds it. It shows the page no `window.webkit` handler and no globals:
    /// requests reach Mote as window events `bridge` handles.
    /// See Scripts/src/passkey-relay.ts.
    ///
    /// The launch's event names are already in the text. ExtensionShims writes
    /// this same text into every extension, and since its version hashes it,
    /// extensions are prepared again each launch and carry that launch's names.
    nonisolated static let page = InjectedScript.source(
        "passkey-relay", config: RelayConfig(askEvent: asked, answerEvent: answered, installEvent: installed))

    /// Runs in Mote's world (`Web.world`), out of pages' reach. It passes page
    /// events on to the handler, where WebKit rather than the event names the
    /// frame, and sends the answers back. See Scripts/src/passkey-bridge.ts.
    static let bridge = InjectedScript.source("passkey-bridge", config: BridgeConfig(handler: name, askEvent: asked, answerEvent: answered))

    /// `moteConfig` of Scripts/src/passkey-relay.ts.
    private nonisolated struct RelayConfig: Encodable {
        let askEvent: String
        let answerEvent: String
        let installEvent: String
    }

    /// `moteConfig` of Scripts/src/passkey-bridge.ts.
    private nonisolated struct BridgeConfig: Encodable {
        let handler: String
        let askEvent: String
        let answerEvent: String
    }
}
