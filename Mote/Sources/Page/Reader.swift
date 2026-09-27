import Foundation

/// Reader mode: replaces the page with its main article.
enum Reader {
    /// Replaces the page with its article; returns "read", or "none" when the
    /// page has no article. See Scripts/src/reader.ts.
    static let script = InjectedScript.call("reader")
}
