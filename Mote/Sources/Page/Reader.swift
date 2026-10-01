import Foundation

/// Reader mode: replaces the page with its main article.
enum Reader {
    /// Replaces the page with its article; returns "read", or "none" when the
    /// page has no article. See Scripts/src/reader.ts.
    static let script = InjectedScript.call("reader")

    /// The page's text, read without entering reading mode.
    ///
    /// `script` puts the article on screen, so calling it to read a page for
    /// the model would make the person's page disappear. This returns the text
    /// the page already shows instead, leaving it where it is. The article
    /// `script` finds is the text wanted; exposing that extraction here needs
    /// a script that reads the article without replacing the page.
    static let text = "return document.body ? document.body.innerText : '';"
}
