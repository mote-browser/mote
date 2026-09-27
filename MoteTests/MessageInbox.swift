import WebKit

/// Collects what scripts post to a `window.webkit.messageHandlers` handler.
@MainActor
final class MessageInbox: NSObject, WKScriptMessageHandler {
    private(set) var messages: [Any] = []

    /// The messages that are objects, as most scripts post.
    var records: [[String: Any]] { messages.compactMap { $0 as? [String: Any] } }

    // WebKit delivers script messages on the main thread.
    nonisolated func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { messages.append(message.body) }
    }
}
