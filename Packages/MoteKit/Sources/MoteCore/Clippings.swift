import Foundation

/// Small text transformations for things the browser copies or saves.
public enum Clippings {
    /// A Markdown link to a page. Backslashes are escaped before brackets so
    /// the brackets' escapes aren't doubled.
    public static func markdownLink(title: String, url: URL) -> String {
        let escaped =
            title
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
        return "[\(escaped)](\(url.absoluteString))"
    }

    /// A file name that isn't taken yet: `name`, then "stem 2.ext",
    /// "stem 3.ext" and so on. WebKit won't overwrite an existing file.
    public static func freeName(_ name: String, taken: (String) -> Bool) -> String {
        guard taken(name) else { return name }
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while true {
            let next = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            if !taken(next) { return next }
            n += 1
        }
    }
}
