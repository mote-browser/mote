import MoteCore
import SwiftUI
import WebKit

@MainActor
final class PageView: WKWebView {
    var unpainted = false
    let testInspector = InspectorHost()
    @objc var _inspector: NSObject { testInspector }
}

final class WKInspectorFixtureView: NSView {}

// The production coordinator and stage are under test; the session never loads pages.
@MainActor
final class Tab {
    var responsive: ResponsiveSession?
    var floating = false
    var shownAddress: URL?
    var built: WKWebView? { nil }
    var store: WKWebsiteDataStore { .nonPersistent() }
}

@MainActor
final class ResponsiveSession: ObservableObject {
    @Published var syncing = true
    @Published var scale = 0.5
    @Published var panes: [Int] = []
    var saved: [ResponsiveLayout] = []
    var notice: String?
    var address = ""
    init(store: WKWebsiteDataStore) {}
    static func allows(_ url: URL) -> Bool { ["http", "https"].contains(url.scheme ?? "") }
    func navigate(_ address: String) throws { self.address = address }
    func reload() { fatalError() }
    func add(_ profile: ResponsiveViewport) { fatalError() }
    func save(name: String) throws { fatalError() }
    func apply(_ profiles: [ResponsiveViewport]) { fatalError() }
    func deleteSaved(_ id: UUID) { fatalError() }
    func close() { panes = [] }
}

struct ResponsiveWorkspace: View {
    let session: ResponsiveSession
    var body: some View { Color.clear.frame(minWidth: 2000, minHeight: 2000) }
}

@MainActor
final class InspectorHost: NSObject {
    @objc var delegate: NSObject?
    @objc var isVisible = false
    // Closing reloads the frontend but preserves this exact native web view.
    @objc let extensionHostWebView = WKWebView(frame: .zero)
    var callbacks: [(@convention(block) (NSError?, NSObject?) -> Void)] = []
    var extensions: [InspectorTab] = []
    var delay = false
    var delayTab = false
    var registrations = 0

    @objc(registerExtensionWithID:extensionBundleIdentifier:displayName:completionHandler:)
    func register(
        _ id: NSString, bundle: NSString, name: NSString,
        completion: @escaping @convention(block) (NSError?, NSObject?) -> Void
    ) {
        registrations += 1
        if delay { callbacks.append(completion) } else { complete(completion) }
    }

    func complete(_ completion: @convention(block) (NSError?, NSObject?) -> Void) {
        let object = InspectorTab(identifier: "tab-\(extensions.count)", delayed: delayTab)
        extensions.append(object)
        completion(nil, object)
    }

    @objc(unregisterExtension:completionHandler:)
    func unregister(_ object: NSObject, completion: @convention(block) (NSError?) -> Void) { completion(nil) }

    @objc func close() { isVisible = false }
}

@MainActor
final class InspectorTab: NSObject {
    @objc var delegate: NSObject?
    let identifier: String
    let delayed: Bool
    var completion: (@convention(block) (NSError?, NSString?) -> Void)?
    var creates = 0
    init(identifier: String, delayed: Bool) { self.identifier = identifier; self.delayed = delayed }

    @objc(createTabWithName:tabIconURL:sourceURL:completionHandler:)
    func create(
        _ name: NSString, icon: NSURL, source: NSURL,
        completion: @escaping @convention(block) (NSError?, NSString?) -> Void
    ) {
        creates += 1
        if delayed { self.completion = completion } else { completion(nil, identifier as NSString) }
    }
}

@main
struct LifecycleChecks {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var failures = 0
        func check(_ condition: Bool, _ label: String) {
            print("\(condition ? "PASS" : "FAIL") \(label)")
            if !condition { failures += 1 }
        }

        do {
            let tab = Tab(), host = InspectorHost()
            tab.shownAddress = URL(string: "https://responsive.example/")
            let coordinator = ResponsiveInspector(tab: tab, inspector: host)
            defer { coordinator.dispose() }
            check(host.delegate === coordinator, "Native inspection has a delegate before opening the frontend")
            host.isVisible = true
            coordinator.inspectorFrontendLoaded(host)
            let object = host.extensions[0]
            coordinator.inspectorExtension(object, didShow: object.identifier as NSString, frame: NSObject())
            if let canvas = coordinator.canvas as? NSHostingView<ResponsiveWorkspace> {
                check(canvas.sizingOptions.isEmpty, "SwiftUI content cannot impose a minimum dock size")
                canvas.frame = NSRect(x: 0, y: 200, width: 300, height: 100)
                check(canvas.frame.height == 100, "Canvas accepts a viewport smaller than its content")
            } else {
                check(false, "Selecting Responsive creates its hosting view")
            }
        }
        do {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1200, height: 900),
                styleMask: [.borderless], backing: .buffered, defer: false)
            let stage = StageView()
            window.contentView = stage
            let page = PageView()
            stage.show(page)
            page.testInspector.isVisible = true
            stage.addSubview(WKInspectorFixtureView())
            page.frame = NSRect(x: 0, y: 200, width: 1200, height: 700)
            let canvas = NSView()
            stage.show(page, overlay: canvas)
            page.frame = NSRect(x: 0, y: 350, width: 1200, height: 550)
            check(canvas.frame == page.frame, "Canvas follows bottom-dock resizing immediately")
            page.frame = NSRect(x: 400, y: 0, width: 800, height: 900)
            check(canvas.frame == page.frame, "Canvas follows side-dock resizing immediately")
            check(canvas.layer?.masksToBounds == true, "Canvas cannot paint over the inspector divider")
            stage.show(nil)
            let detached = canvas.frame
            page.frame.size.width = 600
            check(canvas.frame == detached && canvas.superview == nil, "Detached canvas no longer follows page geometry")
            check(!window.isVisible, "Geometry checks never show a window")
            window.contentView = nil
        }

        do {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1200, height: 900),
                styleMask: [.borderless], backing: .buffered, defer: false)
            let stage = StageView()
            window.contentView = stage
            let page = PageView()
            stage.show(page)
            page.testInspector.isVisible = true
            let dock = WKInspectorFixtureView(frame: NSRect(x: 0, y: 0, width: 1200, height: 200))
            stage.addSubview(dock)
            page.frame = NSRect(x: 0, y: 200, width: 1200, height: 700)
            let canvas = NSView()
            stage.show(page, overlay: canvas)
            // WebKit changes the inspector first, then its attachment view.
            // The canvas must already respect the occupied space between those updates.
            dock.frame.size.height = 350
            check(canvas.frame == NSRect(x: 0, y: 350, width: 1200, height: 550), "Inspector resize reduces available canvas height")
            dock.frame = NSRect(x: 800, y: 0, width: 400, height: 900)
            check(canvas.frame == NSRect(x: 0, y: 0, width: 800, height: 900), "Right dock reduces available canvas width")
            dock.frame = NSRect(x: 0, y: 0, width: 500, height: 900)
            check(canvas.frame == NSRect(x: 500, y: 0, width: 700, height: 900), "Left dock offsets and narrows the canvas")
            stage.show(nil)
            let detached = canvas.frame
            dock.frame.size.width = 600
            check(canvas.frame == detached, "Removing the canvas stops dock-driven updates")
            window.contentView = nil
        }

        do {
            let tab = Tab(), host = InspectorHost()
            let coordinator = ResponsiveInspector(tab: tab, inspector: host)
            defer { coordinator.dispose() }
            for cycle in 1...3 {
                host.isVisible = true
                coordinator.inspectorFrontendLoaded(host)
                check(host.registrations == cycle, "Reopening reused frontend registers panel, cycle \(cycle)")
                check(host.extensions.last?.creates == 1, "Each frontend creates exactly one tab")
                coordinator.installIfReady()
                check(host.registrations == cycle, "Repeated readiness checks do not duplicate registration")
                host.isVisible = false
                coordinator.stop()
            }
        }
        do {
            let tab = Tab(), host = InspectorHost()
            let coordinator = ResponsiveInspector(tab: tab, inspector: host)
            defer { coordinator.dispose() }
            host.isVisible = true
            coordinator.inspectorFrontendLoaded(host)
            coordinator.closeInspector()
            check(coordinator.tabIdentifier == nil, "Explicit closing invalidates cached tab ID immediately")
            coordinator.prepareToOpen()
            check(host.registrations == 1, "Reopening waits for the frontend before registering")
            host.isVisible = true
            coordinator.inspectorFrontendLoaded(host)
            check(host.registrations == 2, "Ordinary DevTools reopening registers the panel")
        }
        do {
            let tab = Tab(), host = InspectorHost()
            host.delay = true
            let coordinator = ResponsiveInspector(tab: tab, inspector: host)
            defer { coordinator.dispose() }
            host.isVisible = true
            coordinator.inspectorFrontendLoaded(host)
            host.isVisible = false
            host.isVisible = true
            coordinator.inspectorFrontendLoaded(host)
            check(host.registrations == 2, "Closing during registration does not block the new frontend")
            if host.callbacks.count == 2 {
                host.complete(host.callbacks[1])
                let current = coordinator.tabIdentifier
                host.complete(host.callbacks[0])
                check(coordinator.tabIdentifier == current, "Stale completion cannot replace the new tab")
                check(host.extensions.last?.creates == 0, "Stale registration cannot create a tab")
            }
            coordinator.dispose()
            for completion in host.callbacks { host.complete(completion) }
            check(coordinator.tabIdentifier == nil, "Disposal rejects pending completions")
        }
        do {
            let tab = Tab(), host = InspectorHost()
            host.delayTab = true
            let coordinator = ResponsiveInspector(tab: tab, inspector: host)
            defer { coordinator.dispose() }
            host.isVisible = true
            coordinator.inspectorFrontendLoaded(host)
            let old = host.extensions[0]
            coordinator.inspectorFrontendLoaded(host)
            let current = host.extensions[1]
            current.completion?(nil, current.identifier as NSString)
            old.completion?(nil, old.identifier as NSString)
            check(coordinator.tabIdentifier == current.identifier, "Stale tab creation cannot overwrite the current tab")
            check(old.delegate == nil, "The old extension delegate is detached")
        }
        do {
            let tab = Tab(), host = InspectorHost()
            host.delay = true
            let coordinator = ResponsiveInspector(tab: tab, inspector: host)
            defer { coordinator.dispose() }
            host.isVisible = true
            coordinator.inspectorFrontendLoaded(host)
            host.callbacks[0](NSError(domain: "test", code: 1), nil)
            coordinator.installIfReady()
            check(host.registrations == 2, "A failed registration can be retried")
            host.complete(host.callbacks[1])
            check(coordinator.tabIdentifier != nil && coordinator.failure == nil, "Successful retry clears the failure")
        }
        if failures > 0 { exit(1) }
    }
}
