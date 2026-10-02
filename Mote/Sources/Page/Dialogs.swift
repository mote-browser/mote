import AppKit
import MoteCore
import WebKit

// What pages ask of the person: alert, confirm and prompt, choosing files,
// signing in, and going on past a bad certificate. WebKit quietly refuses
// all of these (confirm() gives false) unless someone answers, so each
// becomes a sheet on the page's window.

extension Browser {
    // MARK: - alert, confirm, prompt

    func webView(
        _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        Dialogs.ask(Dialogs.fromPage(frame, message, buttons: ["OK"]), over: webView) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        Dialogs.ask(Dialogs.fromPage(frame, message, buttons: ["OK", "Cancel"]), over: webView, then: completionHandler)
    }

    func webView(
        _ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let alert = Dialogs.fromPage(frame, prompt, buttons: ["OK", "Cancel"])
        let field = Dialogs.field(NSTextField.self, text: defaultText ?? "")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        Dialogs.ask(alert, over: webView) { ok in completionHandler(ok ? field.stringValue : nil) }
    }

    // MARK: - Choosing files

    func webView(
        _ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.resolvesAliases = true
        let chosen = { (answer: NSApplication.ModalResponse) in completionHandler(answer == .OK ? panel.urls : nil) }
        if let window = Dialogs.window(for: webView) {
            panel.beginSheetModal(for: window, completionHandler: chosen)
        } else {
            chosen(panel.runModal())
        }
    }

    // MARK: - Certificates and sign-in

    func webView(
        _ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodServerTrust:
            trust(challenge, from: webView, completionHandler)
        case NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest, NSURLAuthenticationMethodNTLM:
            signIn(challenge, from: webView, completionHandler)
        default:
            completionHandler(.performDefaultHandling, nil)
        }
    }

    /// Every HTTPS connection comes here. A certificate the Mac doesn't trust
    /// fails the load, and the failure page offers a way past it; once taken,
    /// the host is let through for the rest of the launch.
    private func trust(
        _ challenge: URLAuthenticationChallenge, from webView: WKWebView,
        _ done: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let trust = challenge.protectionSpace.serverTrust else { return done(.performDefaultHandling, nil) }
        let host = challenge.protectionSpace.host
        switch Challenge.trust(valid: SecTrustEvaluateWithError(trust, nil), host: host, excused: Dialogs.excused) {
        case .usual:
            done(.performDefaultHandling, nil)
        case .accept:
            done(.useCredential, URLCredential(trust: trust))
        }
    }

    /// HTTP Basic, Digest and NTLM: a name and a password, asked twice at most.
    private func signIn(
        _ challenge: URLAuthenticationChallenge, from webView: WKWebView,
        _ done: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let failures = challenge.previousFailureCount
        guard Challenge.mayAskToSignIn(failures: failures) else { return done(.cancelAuthenticationChallenge, nil) }
        let space = challenge.protectionSpace
        var text = space.realm.map { "“\($0)”" } ?? "The site wants a name and a password."
        if failures > 0 { text += "\nThat wasn't accepted — try again." }
        let alert = Dialogs.alert("\(space.host) asks you to sign in", text, buttons: ["Sign In", "Cancel"])

        let name = Dialogs.field(NSTextField.self, placeholder: "Name")
        let password = Dialogs.field(NSSecureTextField.self, placeholder: "Password")
        name.nextKeyView = password
        let fields = NSStackView(views: [name, password])
        fields.orientation = .vertical
        fields.spacing = 8
        fields.frame.size = NSSize(width: Dialogs.fieldWidth, height: 56)
        alert.accessoryView = fields
        alert.window.initialFirstResponder = name

        Dialogs.ask(alert, over: webView) { signs in
            guard signs else { return done(.cancelAuthenticationChallenge, nil) }
            done(.useCredential, URLCredential(user: name.stringValue, password: password.stringValue, persistence: .forSession))
        }
    }

    // MARK: - A page that died

    /// The system can end a page's process when memory runs short, leaving
    /// the tab blank. The tab in front loads again now, others when picked.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard let tab = tab(for: webView) else { return }
        if tab.id == activeID, !tab.isBlank {
            tab.recoverFromCrash()
        } else {
            tab.stale = true
        }
    }
}

/// Sheets over a page.
enum Dialogs {
    /// Hosts whose bad certificates the person let through since launch.
    static var excused = Set<String>()

    static let fieldWidth: CGFloat = 260

    static func alert(_ title: String, _ text: String, buttons: [String], style: NSAlert.Style = .informational) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = style
        buttons.forEach { alert.addButton(withTitle: $0) }
        return alert
    }

    /// Something a page says, headed with the site saying it.
    static func fromPage(_ frame: WKFrameInfo, _ text: String, buttons: [String]) -> NSAlert {
        alert(Challenge.dialogTitle(host: frame.securityOrigin.host), text, buttons: buttons)
    }

    static func field<Field: NSTextField>(_ kind: Field.Type, text: String = "", placeholder: String? = nil) -> Field {
        let field = Field(frame: NSRect(x: 0, y: 0, width: fieldWidth, height: 24))
        field.stringValue = text
        field.placeholderString = placeholder
        return field
    }

    /// The page's window; a tab in the background has none, so the browser's.
    static func window(for webView: WKWebView) -> NSWindow? {
        webView.window ?? NSApp.mainWindow ?? NSApp.windows.first { $0.contentView != nil && $0.isVisible }
    }

    /// Shows the alert as a sheet and hears whether its first button was pressed.
    static func ask(_ alert: NSAlert, over webView: WKWebView, then answer: @escaping (Bool) -> Void) {
        let heard = { (response: NSApplication.ModalResponse) in answer(response == .alertFirstButtonReturn) }
        if let window = window(for: webView) {
            alert.beginSheetModal(for: window, completionHandler: heard)
        } else {
            heard(alert.runModal())
        }
    }
}
