import Foundation

/// JavaScript that Mote injects into web pages. The sources are TypeScript in
/// `Scripts/src` (see `Scripts/README.md`); `make scripts` builds them into
/// `Mote/Resources/Scripts`, which ships in the app bundle.
enum InjectedScript {
    /// The built script named `name` (without the `.js` extension).
    nonisolated static func source(_ name: String) -> String {
        guard
            let url = Bundle.main.url(forResource: name, withExtension: "js")
                ?? Bundle.main.url(forResource: name, withExtension: "js", subdirectory: "Scripts"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            preconditionFailure("\(name).js is missing from the app bundle; run `make scripts`.")
        }
        return source
    }

    /// The script named `name`, with `config` available to it as `moteConfig`.
    /// The value is encoded as JSON, so no Swift string ever becomes code.
    nonisolated static func source(_ name: String, config: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let json = try? encoder.encode(config) else {
            preconditionFailure("The configuration for \(name).js can't be encoded as JSON.")
        }
        return "(() => {\nconst moteConfig = \(String(decoding: json, as: UTF8.self));\n\(source(name))\n})();"
    }

    /// A function body for `callAsyncJavaScript` that runs the script `name` and
    /// returns what its `run()` returns, passing `arguments` (the keys of the
    /// `arguments` dictionary given to `callAsyncJavaScript`) in order. The
    /// script's `mote<Name>` global stays local to the call.
    nonisolated static func call(_ name: String, arguments: [String] = []) -> String {
        source(name) + "\nreturn \(globalName(name)).run(\(arguments.joined(separator: ", ")));"
    }

    /// The name Rolldown gives a script's exports: `reader` → `moteReader`.
    nonisolated static func globalName(_ name: String) -> String {
        "mote" + name.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }
}
