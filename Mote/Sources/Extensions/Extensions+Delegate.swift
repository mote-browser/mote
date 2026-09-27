import AppKit
import MoteCore
import WebKit

// What WebKit asks the browser on extensions' behalf.

@available(macOS 15.4, *)
extension Extensions: WKWebExtensionControllerDelegate {
    func webExtensionController(
        _ controller: WKWebExtensionController, openWindowsFor extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] {
        [window]
    }

    func webExtensionController(
        _ controller: WKWebExtensionController, focusedWindowFor extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        window
    }

    func webExtensionController(
        _ controller: WKWebExtensionController, openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for extensionContext: WKWebExtensionContext
    ) async throws -> (any WKWebExtensionTab)? {
        guard let browser else { return nil }
        let tab = browser.open(configuration.url ?? URL(string: "about:blank")!, foreground: configuration.shouldBeActive, atEnd: true)
        if configuration.shouldBePinned { browser.pin(tab) }
        return adapter(for: tab)
    }

    /// There's one window: a new one's tabs open in it.
    func webExtensionController(
        _ controller: WKWebExtensionController, openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for extensionContext: WKWebExtensionContext
    ) async throws -> (any WKWebExtensionWindow)? {
        guard let browser else { return nil }
        for (index, page) in configuration.tabURLs.enumerated() {
            browser.open(page, foreground: index == 0 && configuration.shouldBeFocused, atEnd: true)
        }
        return window
    }

    func webExtensionController(
        _ controller: WKWebExtensionController, openOptionsPageFor extensionContext: WKWebExtensionContext
    ) async throws {
        openOptions(extensionContext.uniqueIdentifier)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController, promptForPermissions permissions: Set<WKWebExtension.Permission>,
        in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext
    ) async -> (Set<WKWebExtension.Permission>, Date?) {
        let names = permissions.map(\.rawValue).sorted().joined(separator: ", ")
        return await ask("asks for more access", detail: names, context: extensionContext) ? (permissions, nil) : ([], nil)
    }

    /// WebKit, like Safari, asks whenever an extension touches a page outside
    /// its sites, often with nobody doing anything. Chrome never asks here,
    /// so the answer is a quiet no.
    func webExtensionController(
        _ controller: WKWebExtensionController, promptForPermissionToAccess urls: Set<URL>, in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext
    ) async -> (Set<URL>, Date?) {
        let hosts = Set(urls.compactMap { $0.host() }).sorted().joined(separator: ", ")
        asked.append("(refused) \(extensionContext.webExtension.displayName ?? "?") → \(hosts)")
        return ([], nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController, promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
        in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext
    ) async -> (Set<WKWebExtension.MatchPattern>, Date?) {
        let everywhere = matchPatterns.contains { $0.matchesAllHosts || $0.matchesAllURLs }
        let what = everywhere ? "every website" : matchPatterns.map(\.string).sorted().joined(separator: ", ")
        let yes = await ask("wants to read and change \(what)", detail: "Until you remove the extension.", context: extensionContext)
        return yes ? (matchPatterns, nil) : ([], nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController, didUpdate action: WKWebExtension.Action, forExtensionContext context: WKWebExtensionContext
    ) {
        actionsChanged += 1
    }

    /// In Mote's own popover (ExtensionPopup); WebKit's popup only says where.
    func webExtensionController(
        _ controller: WKWebExtensionController, presentActionPopup action: WKWebExtension.Action, for context: WKWebExtensionContext
    ) async throws {
        let page = action.popupWebView?.url ?? Self.popupURL(for: context)
        action.closePopup()
        if let page { ExtensionPopup.shared.show(page, for: context, from: anchor(for: context.uniqueIdentifier)) }
    }

    /// runtime.sendNativeMessage: to Mote's own answers (ExtensionShims), or
    /// to an app's Chrome native messaging host.
    func webExtensionController(
        _ controller: WKWebExtensionController, sendMessage message: Any, toApplicationWithIdentifier applicationIdentifier: String?,
        for extensionContext: WKWebExtensionContext
    ) async throws -> Any? {
        guard let app = applicationIdentifier, app != ExtensionShims.application else {
            return try await ExtensionShims.answer(message, from: extensionContext, owner: self)
        }
        let id = extensionContext.uniqueIdentifier
        do {
            return try await NativeMessaging.send(message, to: app, from: id)
        } catch {
            // A loop of retries gets slowed down.
            if messageFailures.failed(id + "→" + app) { try? await Task.sleep(for: .seconds(1)) }
            throw error
        }
    }

    func webExtensionController(
        _ controller: WKWebExtensionController, connectUsing port: WKWebExtension.MessagePort, for extensionContext: WKWebExtensionContext
    ) async throws {
        switch port.applicationIdentifier {
        case ExtensionSocket.name: ExtensionSocket.connect(port, from: extensionContext.uniqueIdentifier)
        // The shim opens this one only to see how ports behave, and closes it.
        case ExtensionShims.application: return
        default: try NativeMessaging.connect(port, from: extensionContext.uniqueIdentifier)
        }
    }
}
