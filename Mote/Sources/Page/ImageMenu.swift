import AppKit
import MoteCore
import WebKit

// Right-clicking an image shows Mote's own menu. WebKit's Download Image
// skips the navigation delegate, and its Copy Image leaves a promise on the
// pasteboard that some apps never paste; neither can be fixed from outside,
// so the page's script stops WebKit's menu over images and asks for this one.

/// Hears which image was right-clicked.
final class ImageRelay: NSObject, WKScriptMessageHandler {
    static let name = "moteImages"

    /// In every frame; broken images and 1×1 trackers are left alone.
    /// See Scripts/src/image-menu.ts.
    static let watch = InjectedScript.source("image-menu")

    weak var tab: Tab?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let image = (body["src"] as? String).flatMap(ImageAddress.usable) else { return }
        MainActor.assumeIsolated { tab?.imageMenu(for: image) }
    }
}

extension Browser {
    /// Where the pointer is: the ask comes from the page, with no event to
    /// place the menu by.
    func showImageMenu(for tab: Tab, at image: URL) {
        guard let web = tab.built, let window = web.window else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let items: [NSMenuItem] = [
            ActionItem("Open Image in New Tab") { [weak self] in self?.open(image, foreground: true, from: tab) },
            .separator(),
            ActionItem("Copy Image") { [weak self] in self?.copyImage(at: image) },
            ActionItem("Download Image") { [weak self] in self?.downloadImage(at: image, from: web) },
            .separator(),
            ActionItem("Copy Image Address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(image.absoluteString, forType: .string)
            },
        ]
        items.forEach(menu.addItem)
        let pointer = web.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        menu.popUp(positioning: nil, at: pointer, in: web)
    }

    /// The image itself goes on the pasteboard, not a promise of it, so it
    /// pastes anywhere.
    func copyImage(at url: URL) {
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url), let image = NSImage(data: data) else {
                return announce("Couldn't copy that image")
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            announce("Image copied")
        }
    }

    /// Through the usual downloads, like any other.
    func downloadImage(at url: URL, from web: WKWebView) {
        web.startDownload(using: URLRequest(url: url)) { [weak self] download in self?.keep(download) }
    }
}
