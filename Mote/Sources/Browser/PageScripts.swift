import MoteCore
import WebKit

/// The scripts Mote puts in each document a tab loads, in order.
enum PageScripts {
    /// Everything for the next document: scroll reports, the element picker,
    /// sign-in forms, swipes, image menus, the Web Store bridge, link hovers,
    /// middle-clicks, passkeys, and this site's hidden elements (at document
    /// start, so they never show).
    @MainActor
    static func all(hiding: ElementHidingStyle.Config) -> [WKUserScript] {
        var scripts = [
            mote(ScrollRelay.script, at: .atDocumentEnd),
            mote(ElementPicker.picker, at: .atDocumentStart),
            mote(FormRelay.script, at: .atDocumentEnd),
        ]
        if AutoScroll.on { scripts.append(mote(AutoScroll.script, at: .atDocumentEnd)) }
        // Every frame: only a frame's own document knows whether it takes a
        // swipe (a map) or holds the image under the pointer.
        scripts += [
            mote(Swipe.watch, at: .atDocumentStart, everyFrame: true),
            mote(ImageRelay.watch, at: .atDocumentStart, everyFrame: true),
        ]
        if #available(macOS 15.4, *) { scripts.append(mote(WebStoreBridge.script, at: .atDocumentEnd)) }
        if HoveredLink.on {
            scripts.append(
                WKUserScript(source: HoveredLink.script, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .defaultClient))
        }
        // Main frame only: a middle-click in a frame (an ad) isn't the tab's.
        scripts.append(mote(MiddleRelay.watch, at: .atDocumentStart))
        // The passkey patch replaces the page's own functions, so it runs in the
        // page's world and reaches Mote through a bridge in Mote's. It goes in
        // either way, since extension scripts can carry it too (see Passkeys.swift).
        let passkeys = FormRelay.passkeysOffered ? PasskeyRelay.page : FormRelay.withoutPasskeys
        scripts += [
            WKUserScript(source: passkeys, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page),
            mote(PasskeyRelay.bridge, at: .atDocumentStart, everyFrame: true),
        ]
        if !hiding.selectors.isEmpty { scripts.append(mote(ElementPicker.hiding(hiding), at: .atDocumentStart)) }
        return scripts
    }

    @MainActor
    private static func mote(_ source: String, at time: WKUserScriptInjectionTime, everyFrame: Bool = false) -> WKUserScript {
        WKUserScript(source: source, injectionTime: time, forMainFrameOnly: !everyFrame, in: Web.world)
    }
}
