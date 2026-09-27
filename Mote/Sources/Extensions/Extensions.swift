import AppKit
import Combine
import MoteCore
import WebKit

// Chrome extensions, run by WebKit's WKWebExtension. This side gives WebKit
// the browser it asks about (tabs, the window, popups, questions for the
// person), installs from the Chrome Web Store or a folder, keeps them up to
// date, and puts their buttons in the toolbar.
//
// A tab asleep or not yet loaded has no page, and extensions are told so:
// everything here reads `built`, never `web`, which would make one.

typealias Installed = InstalledExtension

@available(macOS 15.4, *)
@MainActor
final class Extensions: NSObject, ObservableObject {
    static let shared = Extensions()

    /// Before the web view is made: its controller can't be set later.
    static func attach(_ configuration: WKWebViewConfiguration) {
        configuration.webExtensionController = shared.controller
    }

    let controller: WKWebExtensionController
    @Published var installed: [Installed] = []
    /// Running extensions, by id.
    @Published var contexts: [String: WKWebExtensionContext] = [:]
    /// Goes up whenever a button's icon, badge or state may have changed.
    @Published var actionsChanged = 0
    /// The id being installed.
    @Published var busy: String?
    /// Each extension's latest errors, oldest first.
    @Published private(set) var errors: [String: [String]] = [:]

    weak var browser: Browser?
    var subscriptions = Set<AnyCancellable>()

    // Tabs as extensions see them (Extensions+Tabs).
    var adapters: [Tab.ID: ExtensionTab] = [:]
    var order: [Tab.ID] = []
    var tabWatches: [Tab.ID: [AnyCancellable]] = [:]
    private(set) lazy var window = ExtensionWindow(owner: self)
    /// The toolbar views popups hang from, by extension id or `menuAnchor`.
    var anchors: [String: WeakView] = [:]
    /// The puzzle button's menu is open.
    @Published var menuOpen = false

    // Keeping extensions alive (below) and installs in flight.
    var restarts = Cooldown(60)
    var reloading: Set<String> = []
    var errorWatches: [String: NSObjectProtocol] = [:]
    /// Native messages that keep failing, by extension and app.
    var messageFailures = FailureThrottle()
    private var loadsThisRun: Set<String> = []
    /// Loaded more than once since launch.
    private(set) var loadedBefore: Set<String> = []

    // Questions (Extensions+Asking).
    var question: Task<Bool, Never>?
    /// The bench's answer to every question, in test runs.
    var answerForTests: Bool?
    /// Every question asked, for the bench.
    var asked: [String] = []

    static var folder: URL { Storage.folder.appendingPathComponent("Extensions", isDirectory: true) }
    static func folder(for id: String) -> URL { folder.appendingPathComponent(id, isDirectory: true) }
    static var list: URL { folder.appendingPathComponent("installed.json") }

    static let scheme = ExtensionRules.scheme
    static func current(_ url: URL) -> URL { ExtensionRules.current(url) }

    private override init() {
        WKWebExtension.MatchPattern.registerCustomURLScheme(Self.scheme)
        // Test runs keep extension data apart.
        let setup: WKWebExtensionController.Configuration =
            Storage.testing && !Storage.ownContainer ? .init(identifier: Storage.probeStore(2)) : .default()
        setup.defaultWebsiteDataStore = Storage.websites
        let pages = setup.webViewConfiguration ?? WKWebViewConfiguration()
        // Otherwise WebKit's default store, not the browser's.
        pages.websiteDataStore = Storage.websites
        // The same as tabs, exactly: a page loading with another user agent
        // makes WebKit restart running workers, and it never restarts an
        // extension's. The shim tells extensions they're in Chrome.
        pages.applicationNameForUserAgent = Web.userAgentName
        // Test runs sit behind other windows, where WebKit slows pages until
        // popup messages stop reaching the worker.
        if Storage.testing, !Storage.measuring { pages.preferences.inactiveSchedulingPolicy = .none }
        setup.webViewConfiguration = pages
        controller = WKWebExtensionController(configuration: setup)
        super.init()
        controller.delegate = self
        installed = (try? JSONDecoder().decode([Installed].self, from: Data(contentsOf: Self.list))) ?? []
    }

    func start(for browser: Browser) {
        self.browser = browser
        followTabs(of: browser)
        // After the window shows: each load holds the main thread for tens of
        // milliseconds.
        AppDelegate.onceShown { [weak self] in
            Task { [weak self] in await self?.loadAll() }
        }
    }

    /// One at a time: started together, WebKit fails some workers and never
    /// tries them again.
    private func loadAll() async {
        for item in installed where item.enabled {
            await load(item)
            if contexts[item.id]?.webExtension.hasBackgroundContent == true { try? await Task.sleep(for: .milliseconds(400)) }
        }
        checkForUpdates()
    }

    func noteError(_ text: String, for id: String) {
        errors[id] = ExtensionRules.noting(text, in: errors[id] ?? [])
    }

    func forgetErrors(of id: String) { errors[id] = nil }

    func save() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(installed).write(to: Self.list, options: .atomic)
    }

    func index(of id: String) -> Int? { installed.firstIndex { $0.id == id } }

    // MARK: - Running

    @discardableResult
    func load(_ item: Installed) async -> Bool {
        // This build's shim, off the main thread: after an app update it
        // rewrites every script and page the extension ships.
        let folder = Self.folder(for: item.id)
        try? await Task.detached(priority: .userInitiated) { try ExtensionShims.prepare(folder) }.value
        do {
            let found = try await WKWebExtension(resourceBaseURL: folder)
            let context = WKWebExtensionContext(for: found)
            context.uniqueIdentifier = item.id
            // The same origin every launch; WebKit would pick a new one and
            // strand the extension's localStorage and IndexedDB.
            if let origin = URL(string: "\(Self.scheme)://\(item.id)/") { context.baseURL = origin }
            context.isInspectable = true
            // What was accepted at install holds on every load; optional
            // permissions are asked for when requested.
            found.requestedPermissions.forEach { context.setPermissionStatus(.grantedExplicitly, for: $0) }
            context.setPermissionStatus(.grantedExplicitly, for: .nativeMessaging)
            found.allRequestedMatchPatterns.forEach { context.setPermissionStatus(.grantedExplicitly, for: $0) }
            try controller.load(context)
            watchErrors(of: context)
            if contexts[item.id] == nil, loadsThisRun.contains(item.id) { loadedBefore.insert(item.id) }
            loadsThisRun.insert(item.id)
            contexts[item.id] = context
            actionsChanged += 1
            return true
        } catch {
            NSLog("Extensions: couldn't load %@: %@", item.id, error.localizedDescription)
            return false
        }
    }

    func unload(_ id: String) {
        guard let context = contexts[id] else { return }
        try? controller.unload(context)
        // WebKit says its ports closed only on the next turn of the run loop.
        DispatchQueue.main.async { NativeMessaging.stopOrphans() }
        contexts[id] = nil
        actionsChanged += 1
    }

    func forgetLoads(of id: String) {
        loadsThisRun.remove(id)
        loadedBefore.remove(id)
    }

    /// Stops and starts an extension, at most once a minute, with its popup
    /// open again if it was.
    func revive(_ id: String, because reason: String) {
        guard let item = installed.first(where: { $0.id == id }), item.enabled, restarts.take(id) else { return }
        noteError("restarted the extension: \(reason)", for: id)
        let popup = ExtensionPopup.shared.extensionID == id ? ExtensionPopup.shared.view?.url : nil
        let anchor = anchor(for: id)
        unload(id)
        Task {
            guard await load(item), let popup, let context = contexts[id] else { return }
            ExtensionPopup.shared.show(popup, for: context, from: anchor)
        }
    }

    /// WebKit never retries a background worker that fails to start; this
    /// notices and starts the extension again.
    private func watchErrors(of context: WKWebExtensionContext) {
        let id = context.uniqueIdentifier
        errorWatches[id].map(NotificationCenter.default.removeObserver)
        errorWatches[id] = NotificationCenter.default.addObserver(
            forName: WKWebExtensionContext.errorsDidUpdateNotification, object: context, queue: .main
        ) { [weak self, weak context] _ in
            MainActor.assumeIsolated {
                guard let self, let context, self.contexts[id] === context, Self.workerFailed(context) else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard let self, self.contexts[id] === context else { return }
                    self.revive(id, because: "its worker failed to start")
                }
            }
        }
    }

    private static func workerFailed(_ context: WKWebExtensionContext) -> Bool {
        context.errors.contains {
            let error = $0 as NSError
            return error.domain == WKWebExtensionContext.errorDomain
                && error.code == WKWebExtensionContext.Error.backgroundContentFailedToLoad.rawValue
        }
    }

    // MARK: - What extensions changed

    /// What an extension set through chrome.privacy and chrome.proxy.
    static func settings(for id: String) -> [String: Any] {
        Storage.settings.dictionary(forKey: "extensions.settings.\(id)") ?? [:]
    }

    static func setSettings(_ values: [String: Any], for id: String) {
        let key = "extensions.settings.\(id)"
        if values.isEmpty { Storage.settings.removeObject(forKey: key) } else { Storage.settings.set(values, forKey: key) }
    }

    /// The enabled extension that turned off Mote's password saving, by name.
    var passwordSavingTakenBy: String? {
        installed.first { $0.enabled && Self.settings(for: $0.id)["privacy.services.passwordSavingEnabled"] as? Bool == false }?.name
    }
}

/// A view held weakly, in a dictionary.
final class WeakView {
    weak var view: NSView?
    init(_ view: NSView) { self.view = view }
}
