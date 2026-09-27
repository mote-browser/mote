import CoreGraphics
import Foundation
import MoteCore

/// What a tab tells the window it belongs to: things its page did that
/// reach beyond the tab. Every method has a do-nothing default.
@MainActor
protocol TabOwner: AnyObject {
    /// The pointer is over a link (its resolved address), or left it.
    func tab(_ tab: Tab, hovers link: String?)
    func tab(_ tab: Tab, zoomedTo level: CGFloat)

    /// An element picked for hiding.
    func tab(_ tab: Tab, hid selector: String, label: String, note: String)
    func tabStoppedPicking(_ tab: Tab)
    func tab(_ tab: Tab, couldNotHide reason: String)

    /// A sign-in field gained focus (its frame in points) or lost it.
    func tab(_ tab: Tab, focusedSignInAt spot: CGRect?)
    /// A sign-in went through.
    func tab(_ tab: Tab, signedIn sent: SentSignIn)

    func tab(_ tab: Tab, openedImageMenuFor image: URL)
    /// "Search with …" from the context menu.
    func tab(_ tab: Tab, searches text: String)
    /// The search engine's name, for that menu item.
    var searchEngineName: String? { get }
    /// "Add to Mote" on a Chrome Web Store page.
    func tabAddsFromStore(_ tab: Tab)
    func tab(_ tab: Tab, middleClicked link: URL)
    /// The page is going between the web and extension pages, which one web
    /// view can't do; the tab has to be replaced.
    func tab(_ tab: Tab, crosses url: URL)
}

extension TabOwner {
    func tab(_ tab: Tab, hovers link: String?) {}
    func tab(_ tab: Tab, zoomedTo level: CGFloat) {}
    func tab(_ tab: Tab, hid selector: String, label: String, note: String) {}
    func tabStoppedPicking(_ tab: Tab) {}
    func tab(_ tab: Tab, couldNotHide reason: String) {}
    func tab(_ tab: Tab, focusedSignInAt spot: CGRect?) {}
    func tab(_ tab: Tab, signedIn sent: SentSignIn) {}
    func tab(_ tab: Tab, openedImageMenuFor image: URL) {}
    func tab(_ tab: Tab, searches text: String) {}
    var searchEngineName: String? { nil }
    func tabAddsFromStore(_ tab: Tab) {}
    func tab(_ tab: Tab, middleClicked link: URL) {}
    func tab(_ tab: Tab, crosses url: URL) {}
}
