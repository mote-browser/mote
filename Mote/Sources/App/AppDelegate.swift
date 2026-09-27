import AppKit

/// The app's delegate: links from other apps (Mote declares http and https
/// in Info.plist), files, the Dock, and quitting.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The browser window, once it exists.
    static weak var window: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        CrashLog.start()
        // Links are taken straight from the Apple Event: through SwiftUI, every
        // link at launch would present the window again.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(openLink(_:reply:)), forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
    }

    /// SwiftUI makes no window for a launch that isn't the usual one (`open
    /// -j`, a link), so one is asked for; a hidden launch stays hidden.
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool == false else { return }
        Task { @MainActor in
            if !NSApp.windows.contains(where: { $0.contentView != nil && !($0 is NSPanel) }) { LinkInbox.openWindow() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { LinkInbox.browser?.flushSession() }
    }

    @objc private func openLink(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue, let url = URL(string: text),
            url.scheme?.lowercased().hasPrefix("http") == true
        else { return }
        MainActor.assumeIsolated { LinkInbox.take(url) }
    }

    /// Web addresses, and local .html and .xhtml files (declared in Info.plist).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.isFileURL || url.scheme?.lowercased().hasPrefix("http") == true {
            MainActor.assumeIsolated { LinkInbox.take(url) }
        }
    }

    /// A click on the Dock icon brings the window back; a SwiftUI window with a
    /// hidden title bar doesn't by itself.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows visible: Bool) -> Bool {
        if !visible { NSApp.windows.first { $0.contentView != nil }?.makeKeyAndOrderFront(nil) }
        return true
    }

    /// Hands links to `browser` from now on, and those that came before it.
    @MainActor static func hand(to browser: Browser) { LinkInbox.connect(browser) }

    /// Runs `then` once a window shows (or after about a second).
    @MainActor static func onceShown(_ then: @escaping () -> Void) {
        Task {
            await LinkInbox.windowShown()
            then()
        }
    }

    static var isDefault: Bool { DefaultBrowser.isMote }
    static func becomeDefault(_ done: @escaping (Bool) -> Void) { DefaultBrowser.ask(done) }
    static func writeFeedback() { Feedback.write() }
}

/// Links from other apps: kept until the browser is ready, then opened.
@MainActor
enum LinkInbox {
    private(set) static weak var browser: Browser?
    private static var waiting: [URL] = []
    private static var askedForWindow = false

    static func take(_ url: URL) {
        guard let browser else {
            waiting.append(url)
            Task { @MainActor in openWindow() }
            return
        }
        open(url, in: browser)
    }

    /// Links that came before the window: the first into its blank tab, the
    /// rest in background tabs a little apart, so the first frame isn't held up.
    static func connect(_ browser: Browser) {
        self.browser = browser
        let early = waiting
        waiting = []
        guard let first = early.first else { return }
        Task {
            await windowShown()
            browser.arrive(first)
            NSApp.activate()
            for (n, url) in early.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(0.15 * Double(n + 1)))
                browser.open(url, foreground: false, atEnd: true)
            }
        }
    }

    private static func open(_ url: URL, in browser: Browser) {
        if browser.prefs.littleLinks { return LinkWindow.show(url, for: browser) }
        browser.arrive(url)
        // Bring the window back if it was closed. It's looked for among the app's
        // windows too: a stale reference would open a second one.
        if let window = AppDelegate.window ?? browserWindow() {
            window.makeKeyAndOrderFront(nil)
        } else {
            _ = NSApp.delegate?.applicationOpenUntitledFile?(NSApp)
        }
        NSApp.activate()
    }

    private static func browserWindow() -> NSWindow? {
        let found = NSApp.windows.first { $0.contentView != nil && !($0 is NSPanel) && $0.canBecomeMain }
        if let found { AppDelegate.window = found }
        return found
    }

    /// A link launched the app: SwiftUI skips its window for such launches and
    /// never saw the Apple Event, so the window is asked of SwiftUI's delegate.
    static func openWindow() {
        guard browser == nil, AppDelegate.window == nil, !askedForWindow else { return }
        askedForWindow = true
        _ = NSApp.delegate?.applicationOpenUntitledFile?(NSApp)
    }

    /// Until a window shows, or about a second: a hidden launch has none.
    static func windowShown() async {
        for _ in 0...40 {
            if NSApp.windows.contains(where: { $0.isVisible && $0.contentView != nil }) { return }
            try? await Task.sleep(for: .milliseconds(30))
        }
    }
}

/// Mote as the Mac's web browser.
enum DefaultBrowser {
    private static let probe = URL(string: "https://example.com")!

    static var isMote: Bool {
        NSWorkspace.shared.urlForApplication(toOpen: probe)?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    /// Asks macOS to send http and https here; it asks the user itself.
    /// `done` hears whether both went through.
    static func ask(_ done: @escaping (Bool) -> Void) {
        let app = Bundle.main.bundleURL
        Task { @MainActor in
            var worked = true
            for scheme in ["http", "https"] {
                do { try await NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: scheme) } catch { worked = false }
            }
            done(worked)
        }
    }
}

/// A GitHub issue started with the version details; nothing is sent until
/// the user sends it.
enum Feedback {
    static func write() {
        var issue = URLComponents(string: "https://github.com/mote-browser/mote/issues/new")!
        let about = "Mote \(Updater.version), build \(Updater.build), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        issue.queryItems = [URLQueryItem(name: "body", value: "\n\n—\n\(about)")]
        if let url = issue.url { NSWorkspace.shared.open(url) }
    }
}

/// Uncaught exceptions, written to crash.log in the profile folder. Nothing
/// is sent anywhere.
enum CrashLog {
    static func start() {
        NSSetUncaughtExceptionHandler { exception in
            let entry =
                "\(Date()) — \(exception.name.rawValue): \(exception.reason ?? "?")\n" + exception.callStackSymbols.joined(separator: "\n")
                + "\n\n"
            let file = Storage.file("crash.log")
            if let handle = FileHandle(forWritingAtPath: file.path) {
                handle.seekToEndOfFile()
                handle.write(Data(entry.utf8))
                handle.closeFile()
            } else {
                try? FileManager.default.createDirectory(at: Storage.folder, withIntermediateDirectories: true)
                try? entry.write(to: file, atomically: true, encoding: .utf8)
            }
        }
    }
}
