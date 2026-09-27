import Testing
import WebKit

@testable import Mote

@Suite("Full screen, known early")
@MainActor
struct FullscreenWarningTests {
    /// Browser paints its window black while the tab is immersed (App.swift), so
    /// it must know before WebKit slides the window away: before the page itself
    /// hears `fullscreenchange`, and for the page's own requestFullscreen, which
    /// nothing in Mote's world can see being called.
    @Test("A page's own requestFullscreen immerses the tab before the page hears fullscreenchange")
    func pageFullscreenEarly() async throws {
        let tab = Tab(shy: true)
        let web = tab.web
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = web
        window.orderFrontRegardless()
        defer { window.close() }

        // The page's first word of the change: a capturing listener on the window
        // runs before any on the document, Mote's included.
        let heard = MessageInbox()
        web.configuration.userContentController.add(heard, contentWorld: .page, name: "heard")
        defer { web.configuration.userContentController.removeScriptMessageHandler(forName: "heard", contentWorld: .page) }

        var seen: [(on: Bool, pageHeard: Int, state: WKWebView.FullscreenState)] = []
        let watching = tab.$immersed.dropFirst().sink { on in
            seen.append((on, heard.messages.count, web.fullscreenState))
        }
        defer { watching.cancel() }

        web.loadHTMLString(
            """
            <div id="box" style="height: 100px">Video</div>
            <script>
              addEventListener('fullscreenchange', () => webkit.messageHandlers.heard.postMessage(!!document.fullscreenElement), true);
            </script>
            """, baseURL: URL(string: "https://example.com/"))
        _ = try await eventually { web.isLoading || web.url == nil ? nil : true }

        _ = try await web.callAsyncJavaScript(
            "document.getElementById('box').requestFullscreen(); return null", contentWorld: .page)
        _ = try await eventually { web.fullscreenState == .inFullscreen ? true : nil }
        _ = try await eventually { heard.messages.isEmpty ? nil : true }
        #expect(tab.immersed)

        _ = try await web.callAsyncJavaScript("await document.exitFullscreen(); return null", contentWorld: .page)
        _ = try await eventually { web.fullscreenState == .notInFullscreen ? true : nil }
        _ = try await eventually { tab.immersed ? nil : true }

        let first = try #require(seen.first { $0.on }, "\(seen)")
        #expect(first.pageHeard == 0, "\(seen)")
        #expect(first.state == .enteringFullscreen, "\(seen)")
    }
}
