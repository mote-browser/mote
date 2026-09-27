import Testing
import WebKit

@testable import Mote

/// A page whose video plays two seconds of silence on a loop, built in the page so
/// the test needs no media file.
private let playingVideo = """
    <p id="text">Around the video</p>
    <video id="player" muted loop playsinline style="width: 640px; height: 360px"></video>
    <script>
      const rate = 8000, samples = rate * 2, data = new DataView(new ArrayBuffer(44 + samples * 2));
      const text = (at, value) => [...value].forEach((c, i) => data.setUint8(at + i, c.charCodeAt(0)));
      text(0, 'RIFF'); data.setUint32(4, 36 + samples * 2, true); text(8, 'WAVE'); text(12, 'fmt ');
      data.setUint32(16, 16, true); data.setUint16(20, 1, true); data.setUint16(22, 1, true);
      data.setUint32(24, rate, true); data.setUint32(28, rate * 2, true); data.setUint16(32, 2, true);
      data.setUint16(34, 16, true); text(36, 'data'); data.setUint32(40, samples * 2, true);
      const player = document.getElementById('player');
      player.src = URL.createObjectURL(new Blob([data.buffer], { type: 'audio/wav' }));
      player.play();
    </script>
    """

/// What an `Isolate` command answered, read the way Browser reads it.
private enum Answer: Equatable, Sendable {
    case text(String)
    case flag(Bool)
    case progress(through: Double, playing: Bool)
    case other

    init(_ value: Any?) {
        if let text = value as? String {
            self = .text(text)
        } else if let pair = value as? [Any], pair.count == 2, let through = pair[0] as? Double, let playing = pair[1] as? Bool {
            self = .progress(through: through, playing: playing)
        } else if let flag = value as? Bool {
            self = .flag(flag)
        } else {
            self = .other
        }
    }
}

/// A page that may play media on its own, shown in a window: WebKit loads no media
/// for a page that is out of sight. Close the window when done.
@MainActor
private func floatingPage() -> (WebPage, NSWindow) {
    let configuration = WKWebViewConfiguration()
    configuration.mediaTypesRequiringUserActionForPlayback = []
    let page = WebPage(configuration: configuration)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless], backing: .buffered,
        defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = page.webView
    // Above the test host's own browser window: WebKit pauses media in a page
    // that is covered.
    window.level = .floating
    window.orderFrontRegardless()
    return (page, window)
}

/// Runs an `Isolate` command the way Browser does, and waits for its answer.
@MainActor
private func isolate(_ page: WebPage, _ command: Isolate.Command, seconds: Double = 0) async -> Answer {
    await withCheckedContinuation { continuation in
        page.webView.isolate(command, seconds: seconds) { continuation.resume(returning: Answer($0)) }
    }
}

/// Polls `condition`, a script that returns "true" or "false", for up to ten seconds.
@MainActor
private func waitUntil(_ page: WebPage, _ condition: String) async throws {
    for _ in 0..<200 {
        if try await page.string(condition) == "true" { return }
        try await Task.sleep(for: .milliseconds(50))
    }
    throw TimedOut()
}

@MainActor
private func waitUntilPlaying(_ page: WebPage) async throws {
    try await waitUntil(
        page, "(() => { const v = document.getElementById('player'); return String(!v.paused && v.readyState >= 2) })()")
}

// Serialized: the tests' windows share a place on screen and would cover each other.
@Suite("Floating video script", .serialized)
@MainActor
struct FloatingVideoScriptTests {
    @Test("The script is in the app bundle")
    func bundled() {
        #expect(!InjectedScript.source("floating-video").isEmpty)
    }

    @Test("Isolates the playing video, reports progress, and restores the page")
    func floatsAndLands() async throws {
        let (page, window) = floatingPage()
        defer { window.close() }
        try await page.load(html: playingVideo)
        try await waitUntilPlaying(page)

        #expect(await isolate(page, .on) == .text("floating"))
        #expect(try await page.string("String(document.getElementById('player').hasAttribute('data-mote-float'))") == "true")
        #expect(try await page.string("getComputedStyle(document.getElementById('text')).visibility") == "hidden")
        #expect(try await page.string("getComputedStyle(document.getElementById('player')).position") == "fixed")

        guard case .progress(let through, let playing) = await isolate(page, .progress) else {
            Issue.record("No progress")
            return
        }
        #expect((0...1).contains(through))
        #expect(playing)

        #expect(await isolate(page, .off) == .text("landed"))
        #expect(try await page.string("String(document.documentElement.classList.contains('mote-floating'))") == "false")
        #expect(try await page.string("getComputedStyle(document.getElementById('text')).visibility") == "visible")
        #expect(try await page.string("String(!!document.querySelector('[data-mote-float]'))") == "false")
    }

    @Test("Puts the mark back when the player rebuilds its video")
    func defendsTheMark() async throws {
        let (page, window) = floatingPage()
        defer { window.close() }
        try await page.load(html: playingVideo)
        try await waitUntilPlaying(page)

        #expect(await isolate(page, .on) == .text("floating"))
        _ = try await page.string("document.getElementById('player').removeAttribute('data-mote-float'); ''")
        try await waitUntil(page, "String(document.getElementById('player').hasAttribute('data-mote-float'))")

        _ = await isolate(page, .off)
    }

    @Test("Toggles playback and skips, never before the start")
    func controls() async throws {
        let (page, window) = floatingPage()
        defer { window.close() }
        try await page.load(html: playingVideo)
        try await waitUntilPlaying(page)

        #expect(await isolate(page, .toggle) == .flag(false))
        #expect(try await page.string("String(document.getElementById('player').paused)") == "true")
        #expect(await isolate(page, .skip, seconds: 1) == .flag(true))
        #expect(await isolate(page, .skip, seconds: -60) == .flag(true))
        #expect(try await page.string("String(document.getElementById('player').currentTime)") == "0")
        #expect(await isolate(page, .toggle) == .flag(true))
    }

    @Test("Answers none, leaves the page alone, and reports the idle video paused, when nothing plays")
    func nothingPlaying() async throws {
        let (page, window) = floatingPage()
        defer { window.close() }
        try await page.load(html: #"<p id="text">No video</p><video id="player"></video>"#)

        #expect(await isolate(page, .on) == .text("none"))
        #expect(try await page.string("String(document.documentElement.classList.contains('mote-floating'))") == "false")
        #expect(await isolate(page, .progress) == .progress(through: 0, playing: false))
    }
}
