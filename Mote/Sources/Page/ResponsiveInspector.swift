import Combine
import MoteCore
import SwiftUI
import WebKit

/// A real Web Inspector extension tab. Its pages live in the browser's main stage.
/// These private selectors are checked at runtime, just like the existing inspector actions.
@MainActor
final class ResponsiveInspector: NSObject, WKScriptMessageHandler {
    private weak var tab: Tab?
    private let inspector: NSObject
    private var inspectorExtension: NSObject?
    private var installing = false
    private var ready = false
    private var selecting = false
    private var selected = false
    private var generation = 0
    private var visibility: Task<Void, Never>?
    private weak var host: WKWebView?
    private weak var frontend: WKWebView?
    private var collapsed = false
    private var responsiveState: (viewports: [ResponsiveViewport], scale: Double, syncing: Bool)?
    private var panelURL: URL?
    private(set) var panelReady = false
    private var changes: AnyCancellable?
    private(set) var tabIdentifier: String?
    private(set) var canvas: NSView?
    private(set) var failure: String?

    init(tab: Tab, inspector: NSObject) {
        self.tab = tab
        self.inspector = inspector
        super.init()
        ready = inspector.unpublishedFlag("isVisible") == true && inspector.unpublishedObject("extensionHostWebView") != nil
        setDelegate(self, on: inspector)
    }

    func showResponsive() {
        prepareToOpen()
        selecting = true
        inspector.unpublished("show")
        installIfReady()
        if tabIdentifier != nil { select() }
    }

    /// All browser entry points invalidate a closed frontend before opening it.
    func prepareToOpen() {
        if !collapsed, inspector.unpublishedFlag("isVisible") != true { resetFrontend() }
        expandInspector()
        installIfReady()
    }

    private func expandInspector() {
        guard collapsed else { return }
        collapsed = false
        let stage = tab?.built?.superview as? StageView
        stage?.animateInspectorTransition()
        stage?.setInspectorRail(nil)
        inspector.unpublished("show")
        frontend?.evaluateJavaScript("window.moteInspector?.expand()", completionHandler: nil)
    }

    private func collapseInspector(_ items: [[String: Any]]) {
        guard !collapsed, let stage = tab?.built?.superview as? StageView,
            frontend?.superview === stage, inspector.responds(to: NSSelectorFromString("hide"))
        else { return }
        let scroll = NSScrollView()
        scroll.setAccessibilityIdentifier("devtools-collapsed-rail")
        scroll.drawsBackground = true
        scroll.backgroundColor = Palette.NS.frame
        scroll.hasVerticalScroller = false
        let stack = InspectorRailView()
        func add(_ title: String, _ text: String, _ tag: Int, icon: String = "", selected: Bool = false) {
            let button = InspectorRailButton(title: text, target: self, action: #selector(railAction(_:)))
            if icon.hasPrefix("data:image/png;base64,"), icon.count <= 32768,
                let data = Data(base64Encoded: String(icon.dropFirst(22))), let image = NSImage(data: data) {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = true
                button.image = image
                button.imagePosition = .imageOnly
            }
            button.font = .systemFont(ofSize: 18)
            button.selectedTool = selected
            button.bezelStyle = .recessed
            button.isBordered = false
            button.toolTip = title
            button.setAccessibilityLabel(title)
            button.tag = tag
            button.contentTintColor = Palette.NS.muted
            stack.addSubview(button)
        }
        add("Expand developer tools", "‹", -1)
        for item in items.prefix(24) {
            guard let title = item["title"] as? String, title.count <= 100,
                let index = item["index"] as? Int, (0..<32).contains(index)
            else { continue }
            add(title, String(title.prefix(2)), index, icon: item["icon"] as? String ?? "", selected: item["selected"] as? Bool == true)
        }
        add("Open in separate window", "↗", -2)
        add("Close developer tools", "×", -3)
        scroll.documentView = stack
        stack.setFrameSize(NSSize(width: 52, height: CGFloat(stack.subviews.count * 44 + 14)))
        collapsed = true
        stage.animateInspectorTransition()
        inspector.unpublished("hide")
        stage.setInspectorRail(scroll)
        scroll.contentView.scroll(to: .zero)
        if NSApp.currentEvent?.type == .keyDown, let first = stack.subviews.first {
            stage.window?.makeFirstResponder(first)
        } else {
            stage.window?.makeFirstResponder(tab?.built)
        }
    }

    @objc private func railAction(_ sender: NSButton) {
        if sender.tag == -3 { closeInspector(); return }
        expandInspector()
        if sender.tag == -2 {
            inspector.unpublished("detach")
        } else if sender.tag >= 0 {
            frontend?.evaluateJavaScript("window.moteInspector?.selectTab(\(sender.tag))", completionHandler: nil)
        }
    }

    private func styleFrontend() {
        guard let view = inspector.unpublishedObject("extensionHostWebView") as? WKWebView,
            let cssURL = Bundle.main.url(forResource: "InspectorTheme", withExtension: "css"),
            let scriptURL = Bundle.main.url(forResource: "InspectorTheme", withExtension: "js"),
            let css = try? String(contentsOf: cssURL, encoding: .utf8),
            let script = try? String(contentsOf: scriptURL, encoding: .utf8)
        else { return }
        frontend = view
        view.configuration.userContentController.add(self, name: "moteInspector")
        view.callAsyncJavaScript("return " + script, arguments: ["moteCSS": css], in: nil, in: .page) { [weak self] result in
            if case .failure(let error) = result {
                self?.failure = "Inspector appearance unavailable: \(error.localizedDescription)"
            } else if (try? result.get()) as? Bool != true {
                self?.failure = "This WebKit frontend does not support the Mote inspector appearance."
            }
        }
    }

    func closeInspector() {
        collapsed = false
        (tab?.built?.superview as? StageView)?.setInspectorRail(nil)
        resetFrontend()
        inspector.unpublished("close")
    }

    func installIfReady() {
        guard ready, !installing, inspectorExtension == nil,
            inspector.unpublishedObject("extensionHostWebView") != nil
        else { return }
        let selector = NSSelectorFromString("registerExtensionWithID:extensionBundleIdentifier:displayName:completionHandler:")
        guard inspector.responds(to: selector) else { fail("This version of WebKit cannot add an inspector tab."); return }
        installing = true
        let current = generation
        typealias Callback = @convention(block) (NSError?, NSObject?) -> Void
        let callback: Callback = { [weak self] error, object in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                self.installing = false
                guard error == nil, let object else { self.fail(error?.localizedDescription ?? "Could not register Responsive."); return }
                self.inspectorExtension = object
                self.setDelegate(self, on: object)
                self.host = self.inspector.unpublishedObject("extensionHostWebView") as? WKWebView
                self.host?.configuration.userContentController.add(self, name: "moteResponsivePanel")
                self.createTab(object, generation: current)
            }
        }
        typealias Call = @convention(c) (AnyObject, Selector, NSString, NSString, NSString, Callback) -> Void
        unsafeBitCast(inspector.method(for: selector), to: Call.self)(
            inspector, selector, "mote.responsive", Bundle.main.bundleIdentifier! as NSString, "Responsive", callback)
    }

    private func createTab(_ object: NSObject, generation current: Int) {
        let selector = NSSelectorFromString("createTabWithName:tabIconURL:sourceURL:completionHandler:")
        guard object.responds(to: selector),
            let source = Bundle.main.url(forResource: "ResponsivePanel", withExtension: "html"),
            let icon = Bundle.main.url(forResource: "ResponsivePanel", withExtension: "svg"),
            let html = try? Data(contentsOf: source), let svg = try? Data(contentsOf: icon),
            let sourceURL = URL(string: "data:text/html;base64," + html.base64EncodedString()),
            let iconURL = URL(string: "data:image/svg+xml;base64," + svg.base64EncodedString())
        else { fail("Responsive panel resources or WebKit support are unavailable."); return }
        panelURL = sourceURL
        typealias Callback = @convention(block) (NSError?, NSString?) -> Void
        let callback: Callback = { [weak self] error, identifier in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                guard error == nil, let identifier else { self.fail(error?.localizedDescription ?? "Could not create Responsive."); return }
                self.tabIdentifier = identifier as String
                self.failure = nil
                if self.selecting { self.select() }
            }
        }
        typealias Call = @convention(c) (AnyObject, Selector, NSString, NSURL, NSURL, Callback) -> Void
        unsafeBitCast(object.method(for: selector), to: Call.self)(
            object, selector, "Responsive", iconURL as NSURL, sourceURL as NSURL, callback)
    }

    private func select() {
        guard let tabIdentifier else { return }
        let selector = NSSelectorFromString("showExtensionTabWithIdentifier:completionHandler:")
        guard inspector.responds(to: selector) else { fail("WebKit could not select Responsive."); return }
        let current = generation
        typealias Callback = @convention(block) (NSError?) -> Void
        let callback: Callback = { [weak self] error in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                if let error { self.fail(error.localizedDescription) } else { self.resumeIfSelected() }
            }
        }
        typealias Call = @convention(c) (AnyObject, Selector, NSString, Callback) -> Void
        unsafeBitCast(inspector.method(for: selector), to: Call.self)(inspector, selector, tabIdentifier as NSString, callback)
    }

    private func start() {
        selecting = false
        guard let tab, tab.responsive == nil, !tab.floating,
            let url = tab.shownAddress, ResponsiveSession.allows(url)
        else { return }
        let session = ResponsiveSession(store: tab.store)
        if let responsiveState {
            session.apply(responsiveState.viewports)
            session.scale = responsiveState.scale
            session.syncing = responsiveState.syncing
        }
        do { try session.navigate(url.absoluteString) } catch {
            session.close()
            fail(error.localizedDescription)
            return
        }
        let hosting = NSHostingView(rootView: ResponsiveWorkspace(session: session))
        // WebKit owns the dock geometry. SwiftUI must not impose its content's
        // minimum size on the page or the inspector's resize area.
        hosting.sizingOptions = []
        canvas = hosting
        canvas?.setAccessibilityIdentifier("responsive-canvas")
        tab.responsive = session
        changes = session.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.render()
            }
        }
        render()
        // WebKit's delegate has no close callback. Only watch visibility while previews are alive.
        visibility = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self else { return }
                if !collapsed, inspector.unpublishedFlag("isVisible") != true {
                    resetFrontend()
                    return
                }
            }
        }
    }

    func stop() {
        expandInspector()
        changes = nil
        visibility?.cancel()
        visibility = nil
        let session = tab?.responsive
        if let session {
            responsiveState = (session.panes.map(\.profile), session.scale, session.syncing)
        }
        tab?.responsive = nil
        canvas?.removeFromSuperview()
        canvas = nil
        session?.close()
        render()
    }

    func resumeIfSelected() {
        if selected, inspector.unpublishedFlag("isVisible") == true { start() }
    }

    func dispose() {
        if collapsed { closeInspector() }
        stop()
        generation += 1
        selecting = false
        selected = false
        setDelegate(nil, on: inspector)
        frontend?.configuration.userContentController.removeScriptMessageHandler(forName: "moteInspector")
        frontend = nil
        host?.configuration.userContentController.removeScriptMessageHandler(forName: "moteResponsivePanel")
        host = nil
        panelURL = nil
        panelReady = false
        if let object = inspectorExtension {
            setDelegate(nil, on: object)
            let selector = NSSelectorFromString("unregisterExtension:completionHandler:")
            if inspector.responds(to: selector) {
                typealias Callback = @convention(block) (NSError?) -> Void
                typealias Call = @convention(c) (AnyObject, Selector, NSObject, Callback) -> Void
                let callback: Callback = { _ in }
                unsafeBitCast(inspector.method(for: selector), to: Call.self)(inspector, selector, object, callback)
            }
        }
        inspectorExtension = nil
        tabIdentifier = nil
        installing = false
        ready = false
    }

    private func setDelegate(_ delegate: NSObject?, on object: NSObject) {
        let selector = NSSelectorFromString("setDelegate:")
        if object.responds(to: selector) { object.perform(selector, with: delegate) }
    }

    private func fail(_ message: String) {
        failure = message
        guard selecting else { return }
        selecting = false
        let alert = NSAlert()
        alert.messageText = "Responsive Preview Unavailable"
        alert.informativeText = message
        if let window = tab?.built?.window { alert.beginSheetModal(for: window) }
    }

    @objc(inspectorFrontendLoaded:)
    func inspectorFrontendLoaded(_ object: NSObject) {
        guard object === inspector else { return }
        // The same WKWebView can host a new frontend document. Every load invalidates
        // extension IDs and pending callbacks, regardless of native view identity.
        resetFrontend()
        ready = true
        styleFrontend()
        installIfReady()
    }

    private func resetFrontend() {
        stop()
        frontend?.configuration.userContentController.removeScriptMessageHandler(forName: "moteInspector")
        frontend = nil
        host?.configuration.userContentController.removeScriptMessageHandler(forName: "moteResponsivePanel")
        host = nil
        panelReady = false
        generation += 1
        if let object = inspectorExtension { setDelegate(nil, on: object) }
        inspectorExtension = nil
        tabIdentifier = nil
        installing = false
        ready = false
        selected = false
    }

    @objc(inspectorExtension:didShowTabWithIdentifier:withFrameHandle:)
    func inspectorExtension(_ object: NSObject, didShow identifier: NSString, frame: NSObject) {
        guard object === inspectorExtension, identifier as String == tabIdentifier else { return }
        selected = true
        start()
        render()
    }

    @objc(inspectorExtension:didHideTabWithIdentifier:)
    func inspectorExtension(_ object: NSObject, didHide identifier: NSString) {
        guard object === inspectorExtension, identifier as String == tabIdentifier else { return }
        selected = false
        stop()
    }

    @objc(inspectorExtension:inspectedPageDidNavigate:)
    func inspectorExtension(_ object: NSObject, inspectedPageDidNavigate url: NSURL) {
        guard object === inspectorExtension, let session = tab?.responsive else { return }
        let url = url as URL
        guard ResponsiveSession.allows(url) else { stop(); return }
        if session.address != url.absoluteString {
            do { try session.navigate(url.absoluteString) } catch { session.notice = error.localizedDescription }
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "moteInspector" {
            guard message.webView === frontend, message.frameInfo.isMainFrame,
                let body = message.body as? [String: Any], let action = body["action"] as? String
            else { return }
            switch action {
            case "collapse":
                if let value = body["value"] as? Bool {
                    if value { collapseInspector(body["tabs"] as? [[String: Any]] ?? []) }
                    else { expandInspector() }
                }
            case "close": closeInspector()
            default: break
            }
            return
        }
        guard message.webView === host, message.frameInfo.request.url == panelURL,
            let body = message.body as? [String: Any],
            JSONSerialization.isValidJSONObject(body),
            let data = try? JSONSerialization.data(withJSONObject: body), data.count <= 4096,
            let action = body["action"] as? String
        else { return }
        if action == "ready" { panelReady = true; render(); return }
        guard let session = tab?.responsive else { return }
        switch action {
        case "reload": session.reload()
        case "sync": if let enabled = body["value"] as? Bool { session.syncing = enabled }
        case "scale": if let scale = body["value"] as? Double, [0.25, 0.5, 0.75, 1].contains(scale) { session.scale = scale }
        case "add":
            if let index = body["value"] as? Int, ResponsiveViewport.presets.indices.contains(index) {
                session.add(ResponsiveViewport.presets[index])
            }
        case "save":
            if let name = body["value"] as? String {
                do { try session.save(name: name) } catch { session.notice = error.localizedDescription }
            }
        case "load", "delete":
            if let value = body["value"] as? String, let id = UUID(uuidString: value),
                let layout = session.saved.first(where: { $0.id == id })
            {
                if action == "load" { session.apply(layout.viewports) } else { session.deleteSaved(id) }
            }
        case "defaults": session.apply(ResponsiveViewport.presets)
        default: return
        }
        render()
    }

    private func render() {
        let session = tab?.responsive
        let state: [String: Any] = [
            "active": session != nil,
            "sync": session?.syncing ?? true,
            "scale": session?.scale ?? 0.5,
            "count": session?.panes.count ?? 0,
            "saved": session?.saved.map { ["id": $0.id.uuidString, "name": $0.name] } ?? [],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: state), let json = String(data: data, encoding: .utf8) else { return }
        evaluatePanel("window.moteResponsivePanel?.render(\(json))") { _, _ in }
    }

    /// Evaluate in our extension iframe, never in the inspected website.
    func evaluatePanel(_ script: String, completion: @escaping (NSError?, NSObject?) -> Void) {
        guard let object = inspectorExtension, let tabIdentifier else { return }
        let selector = NSSelectorFromString("evaluateScript:inTabWithIdentifier:completionHandler:")
        guard object.responds(to: selector) else { return }
        typealias Callback = @convention(block) (NSError?, NSObject?) -> Void
        typealias Call = @convention(c) (AnyObject, Selector, NSString, NSString, Callback) -> Void
        let callback: Callback = { error, result in MainActor.assumeIsolated { completion(error, result) } }
        unsafeBitCast(object.method(for: selector), to: Call.self)(
            object, selector, script as NSString, tabIdentifier as NSString, callback)
    }
}

/// Flipped coordinates keep tools at the top; window controls stay at the bottom.
final class InspectorRailButton: NSButton {
    var selectedTool = false { didSet { updateStyle() } }
    private var hovering = false
    private var pointerTracking: NSTrackingArea?

    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTracking { removeTrackingArea(pointerTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        pointerTracking = area
        updateStyle()
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; updateStyle() }
    override func mouseExited(with event: NSEvent) { hovering = false; updateStyle() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateStyle() }

    private func updateStyle() {
        wantsLayer = true
        guard let layer else { return }
        let active = hovering || selectedTool
        let color = (active ? Palette.NS.ground : .clear).cgColor
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let animation = CABasicAnimation(keyPath: "backgroundColor")
            animation.fromValue = layer.presentation()?.backgroundColor ?? layer.backgroundColor
            animation.toValue = color
            animation.duration = 0.12
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(animation, forKey: "hover")
        }
        layer.cornerRadius = 10
        layer.backgroundColor = color
        layer.borderWidth = 1
        layer.borderColor = (active ? Palette.NS.edge : .clear).cgColor
        contentTintColor = active ? Palette.NS.ink : Palette.NS.muted
        if image == nil {
            attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: contentTintColor!, .font: font ?? NSFont.systemFont(ofSize: 18)])
        }
    }
}

private final class InspectorRailView: NSView {
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let tools = max(0, subviews.count - 2)
        for (index, button) in subviews.enumerated() {
            let y: CGFloat = index < tools
                ? 10 + CGFloat(index * 44)
                : max(10 + CGFloat(tools * 44), bounds.height - 92) + CGFloat((index - tools) * 44)
            button.frame = NSRect(x: 7, y: y, width: 38, height: 38)
        }
    }
}
