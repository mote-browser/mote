import Foundation

/// Reader mode: replaces the page with its main article.
enum Reader {
    /// Replaces the page with its article; returns "read", or "none" when the
    /// page has no article. See Scripts/src/reader.ts.
    static let script = InjectedScript.call("reader")

    /// The page's text, read without entering reading mode.
    ///
    /// `script` puts the article on screen, so calling it to read a page for
    /// the model would make the person's page disappear. This reads the same
    /// article through the script's `text()`, which cleans a copy and never
    /// touches the page; when no article scores, it falls back to the page's
    /// own text.
    static let text = InjectedScript.source("reader") + "\nreturn \(InjectedScript.globalName("reader")).text();"
}
