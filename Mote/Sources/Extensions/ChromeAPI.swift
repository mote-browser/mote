import MoteCore
import WebKit

// Mote's answers to the Chrome APIs its shim defines. Each namespace has a
// handler (ChromeAPI+…); permissions are checked here, before any of them,
// because the shim's own checks run in the extension's JavaScript, which it
// can change.

/// One call from an extension's shim.
@available(macOS 15.4, *)
@MainActor
struct ChromeCall {
    /// "namespace.method", or "setting.get:privacy.x" for settings.
    let api: String
    let args: [Any]
    let context: WKWebExtensionContext
    let owner: Extensions
    let browser: Browser

    init(api: String, args: [Any], context: WKWebExtensionContext, owner: Extensions) throws {
        guard let browser = owner.browser else { throw ChromeAPI.Refusal("No browser window") }
        self.api = api
        self.args = args
        self.context = context
        self.owner = owner
        self.browser = browser
    }

    /// The extension's id.
    var id: String { context.uniqueIdentifier }
    var namespace: Substring { api.prefix { $0 != "." } }
    var method: Substring { api.drop { $0 != "." }.dropFirst() }

    func arg(_ index: Int) -> Any? { args.indices.contains(index) ? args[index] : nil }
    var first: Any? { arg(0) }
    /// The first argument as an object: most calls take their options so.
    var options: [String: Any] { first as? [String: Any] ?? [:] }
    func option<Value>(_ key: String) -> Value? { options[key] as? Value }

    /// The manifest's permissions, and the optional ones granted since.
    var allowed: Set<String> {
        let declared = (context.webExtension.manifest["permissions"] as? [Any] ?? []).compactMap { $0 as? String }
        return Set(declared + ChromeAPI.granted(to: id))
    }
}

@available(macOS 15.4, *)
@MainActor
enum ChromeAPI {
    /// Why a call was refused, as the extension's lastError reads.
    struct Refusal: LocalizedError {
        let errorDescription: String?
        init(_ reason: String) { errorDescription = reason }

        static func notAsked(_ permission: String) -> Refusal { Refusal("The extension never asked for \u{201C}\(permission)\u{201D}") }
    }

    typealias Handler = @MainActor (ChromeCall) async throws -> Any?

    /// Each namespace's handler.
    private static let handlers: [Substring: Handler] = [
        "bookmarks": bookmarks, "history": history, "downloads": downloads, "sessions": sessions, "topSites": topSites,
        "readingList": readingList, "browsingData": browsingData, "sidePanel": sidePanel, "offscreen": offscreen,
        "management": management, "runtime": runtime, "background": background, "debug": debug, "action": action,
        "permissions": permissions, "tabs": tabs, "search": search, "userScripts": userScripts, "fontSettings": fontSettings,
        "i18n": i18n, "notifications": notifications, "tts": tts, "idle": idle, "power": power, "system": system,
        "tabGroups": tabGroups, "identity": identity, "setting": setting,
    ]

    static func run(_ call: ChromeCall) async throws -> Any? {
        try check(call)
        guard let handler = handlers[call.namespace] else { throw unavailable(call) }
        return try await handler(call)
    }

    private static func check(_ call: ChromeCall) throws {
        if call.namespace == "setting" {
            guard let family = ChromeAPIRules.settingFamily(of: call.api), call.allowed.contains(family) else {
                throw Refusal.notAsked(ChromeAPIRules.settingFamily(of: call.api) ?? "")
            }
        }
        // Tab details come with WebKit's own `tabs` permission, optional grants included.
        if call.api == "tabs.describe", !call.context.hasPermission(.tabs) { throw Refusal.notAsked("tabs") }
        if let needed = ChromeAPIRules.gate(for: call.api), !call.allowed.contains(needed) { throw Refusal.notAsked(needed) }
    }

    static func unavailable(_ call: ChromeCall) -> Refusal { Refusal("\(call.api) isn't available in Mote") }

    // MARK: - Optional permissions granted since install

    private static func grantedKey(_ id: String) -> String { "extensions.granted.\(id)" }

    static func granted(to id: String) -> [String] { Storage.settings.stringArray(forKey: grantedKey(id)) ?? [] }

    static func setGranted(_ permissions: [String], to id: String) {
        Storage.settings.set(Array(Set(permissions)).sorted(), forKey: grantedKey(id))
    }
}
