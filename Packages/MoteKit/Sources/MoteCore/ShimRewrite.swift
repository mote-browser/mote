import Foundation

/// How Mote's shim is written into an extension: which files, and what
/// changes in its manifest, its worker and its pages. Only text here; the
/// app reads and writes the files.
public enum ShimRewrite {
    /// The shim, beside the extension's own files.
    public static let file = "mote-shim.js"
    /// The passkey patch, run before every MAIN-world content script.
    public static let passkeys = "mote-passkeys.js"
    /// What a worker with the shim written in starts and ends with.
    public static let marker = "/* Mote: Chrome APIs WebKit lacks, filled in (ExtensionShims.swift) */"
    public static let ender = "/* Mote: end of shim */"
    /// Which shim an extension was prepared with.
    public static let stamp = ".mote-shim"
    /// The permissions Mote added to the manifest, as a JSON list.
    public static let added = ".mote-added"

    /// The manifest with what the shim needs: nativeMessaging, to reach Mote,
    /// and scripting when userScripts is asked for (Mote builds it on
    /// registered content scripts); the shim first among background scripts
    /// and content scripts; the passkey patch before MAIN-world ones. `added`
    /// keeps what Mote put in, so the person is only asked about the rest.
    public static func manifest(_ manifest: [String: Any], added: [String]) -> (manifest: [String: Any], added: [String]) {
        var manifest = manifest
        var permissions = manifest["permissions"] as? [Any] ?? []
        let asked = Set(permissions.compactMap { $0 as? String })
        var added = added
        for needed in ["nativeMessaging"] + (asked.contains("userScripts") ? ["scripting"] : []) where !asked.contains(needed) {
            permissions.append(needed)
            added.append(needed)
        }
        manifest["permissions"] = permissions
        // WebKit runs `scripts` as a background page even beside a worker.
        if var background = manifest["background"] as? [String: Any] {
            if var scripts = background["scripts"] as? [String] {
                if scripts.first != file { scripts.insert(file, at: 0) }
                background["scripts"] = scripts
            }
            manifest["background"] = background
        }
        // Password managers take navigator.credentials as they load, so the
        // patch must be in place before them.
        if let entries = manifest["content_scripts"] as? [[String: Any]] {
            manifest["content_scripts"] = entries.map { entry in
                guard var js = entry["js"] as? [String] else { return entry }
                var entry = entry
                if !js.contains(file) { js.insert(file, at: 0) }
                if (entry["world"] as? String)?.uppercased() == "MAIN", !js.contains(passkeys) { js.insert(passkeys, at: 0) }
                entry["js"] = js
                return entry
            }
        }
        return (manifest, Array(Set(added)).sorted())
    }

    /// The manifest's service worker, and whether it's a module.
    public static func worker(in manifest: [String: Any]) -> (path: String, module: Bool)? {
        guard let background = manifest["background"] as? [String: Any], let path = background["service_worker"] as? String else {
            return nil
        }
        return (path, (background["type"] as? String) == "module")
    }

    /// The worker with the shim: written in ahead of a classic worker, and
    /// imported by a module one, since imports run before any code. A shim
    /// written in before is taken out first.
    public static func worker(_ source: String, shim: String, module: Bool) -> String {
        let source = withoutShim(source)
        return module ? importLine + source : marker + "\n" + shim + "\n" + ender + "\n" + source
    }

    private static let importLine = "import \"/\(file)\";\n"

    /// The worker as the extension shipped it.
    public static func withoutShim(_ source: String) -> String {
        var source = source
        if source.hasPrefix(marker), let end = source.range(of: ender) {
            source = String(String(source[end.upperBound...]).trimmingPrefix("\n"))
        }
        // Older shims had no end marker and ended at the first `})();` line.
        while source.hasPrefix(marker), let end = source.range(of: "\n})();\n") {
            source = String(source[end.upperBound...])
        }
        while source.hasPrefix(importLine) { source.removeFirst(importLine.count) }
        return source
    }

    /// A page with the shim's script tag, first in its head; nil when it
    /// has it already.
    public static func page(_ html: String) -> String? {
        guard !html.contains(file) else { return nil }
        let tag = "<script src=\"/\(file)\"></script>"
        var html = html
        if let head = html.range(of: "<head[^>]*>", options: [.regularExpression, .caseInsensitive]) {
            html.insert(contentsOf: tag, at: head.upperBound)
        } else {
            html = tag + html
        }
        return html
    }

    private static let eventPattern = try! NSRegularExpression(pattern: #"\.([a-zA-Z]+)\.(on[A-Z][A-Za-z]+)\b"#)

    /// The `namespace.onEvent` names a script mentions, so the shim can hold
    /// on to events for listeners added late.
    public static func events(in script: String) -> Set<String> {
        var text = script
        if text.hasPrefix(marker), let end = text.range(of: ender) { text = String(text[end.upperBound...]) }
        let range = NSRange(text.startIndex..., in: text)
        return Set(
            eventPattern.matches(in: text, range: range).compactMap { match in
                guard let a = Range(match.range(at: 1), in: text), let b = Range(match.range(at: 2), in: text) else { return nil }
                return "\(text[a]).\(text[b])"
            })
    }

    /// The list of the extension's scripts the shim gets, by path from the
    /// extension's root: Mote's own two whether written yet or not (so the
    /// first preparation matches the next), and an empty one marked "-".
    public static func scriptList(_ scripts: [(path: String, empty: Bool)]) -> [String] {
        let own = ["/" + file, "/" + passkeys]
        return (own + scripts.filter { !own.contains($0.path) }.map { ($0.empty ? "-" : "") + $0.path }).sorted()
    }
}
