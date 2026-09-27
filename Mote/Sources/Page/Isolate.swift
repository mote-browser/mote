import WebKit

/// The page's side of the floating video: it hides all but the video while
/// the page floats, and answers the window's buttons.
/// See Scripts/src/floating-video.ts.
enum Isolate {
    enum Command: String {
        /// Hides all but the biggest playing video with CSS visibility, leaving
        /// the page's structure alone so the player keeps streaming. Answers
        /// "floating", or "none" when nothing plays.
        case on
        /// Puts the page back. Answers "landed".
        case off
        /// Plays or pauses. Answers whether it plays now.
        case toggle
        /// Answers [how far played, from 0 to 1, whether it plays].
        case progress
        /// Jumps by `seconds`. Answers whether there was a video.
        case skip
    }

    static let script = InjectedScript.call("floating-video", arguments: ["command", "seconds"])
}

extension WKWebView {
    /// Runs an Isolate command in the main frame, in Mote's world; `then`
    /// hears the answer, or nil on an error.
    func isolate(_ command: Isolate.Command, seconds: Double = 0, then: ((Any?) -> Void)? = nil) {
        callAsyncJavaScript(Isolate.script, arguments: ["command": command.rawValue, "seconds": seconds], in: nil, in: Web.world) {
            then?(try? $0.get())
        }
    }
}
