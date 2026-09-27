import WebKit

/// A page's sound, through the private WebKit calls Safari uses. When a call
/// is missing the feature quietly does nothing.
enum PageAudio {
    /// Mutes or unmutes the page without pausing it. `_mediaMutedState` is a
    /// bitmask: the low bit is the page's audio; the others are camera and
    /// microphone and are left alone.
    static func mute(_ muted: Bool, _ web: WKWebView) {
        let read = NSSelectorFromString("_mediaMutedState")
        let write = NSSelectorFromString("_setPageMuted:")
        guard web.responds(to: read), web.responds(to: write) else { return }
        typealias Read = @convention(c) (AnyObject, Selector) -> UInt
        typealias Write = @convention(c) (AnyObject, Selector, UInt) -> Void
        let state = unsafeBitCast(web.method(for: read), to: Read.self)(web, read)
        unsafeBitCast(web.method(for: write), to: Write.self)(web, write, muted ? state | 1 : state & ~1)
    }
}

/// Reports whether a page is playing sound, from WebKit's private
/// `_isPlayingAudio`. Without it tabs just show no speaker.
final class AudioWatch: NSObject {
    private nonisolated static let key = "_isPlayingAudio"

    private weak var web: WKWebView?
    private var report: ((Bool) -> Void)?

    func watch(_ web: WKWebView, _ report: @escaping (Bool) -> Void) {
        guard web.responds(to: NSSelectorFromString(Self.key)) else { return }
        stop()
        self.web = web
        self.report = report
        web.addObserver(self, forKeyPath: Self.key, options: [.new], context: nil)
    }

    func stop() {
        web?.removeObserver(self, forKeyPath: Self.key)
        web = nil
        report = nil
    }

    // WebKit reports its own properties on the main thread.
    nonisolated override func observeValue(
        forKeyPath path: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?
    ) {
        guard path == Self.key else { return }
        let playing = change?[.newKey] as? Bool ?? false
        MainActor.assumeIsolated { report?(playing) }
    }

    deinit {
        web?.removeObserver(self, forKeyPath: Self.key)
    }
}
