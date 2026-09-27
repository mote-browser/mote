import CryptoKit
import MoteCore
import WebKit

// chrome.userScripts, built on registered content scripts: each script is
// written out as a file that checks its globs and, in the USER_SCRIPT world,
// gets a narrower `chrome`. Files are named by their contents, so WebKit
// never serves an old copy.

@available(macOS 15.4, *)
extension ExtensionShims {
    /// A script Chrome would refuse to register; the extension hears why.
    struct InvalidUserScript: LocalizedError {
        let property: String
        var errorDescription: String? { "Error at property '\(property)': Invalid type: expected an array of strings." }
    }

    /// Writes the script's file, if it isn't there, and gives its path in the extension.
    static func userScriptFile(_ script: [String: Any], in folder: URL) throws -> String {
        let include = try globs(script, "includeGlobs")
        let exclude = try globs(script, "excludeGlobs")
        let code = (script["js"] as? [[String: Any]] ?? []).compactMap { source -> String? in
            if let inline = source["code"] as? String { return inline }
            // Files only from inside the extension.
            return (source["file"] as? String).flatMap { inside($0, of: folder) }.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        }
        .map { $0 + "\n;\n" }.joined()
        let userWorld = (script["world"] as? String) != "MAIN"
        // Scripts/src/user-script.ts decides whether it runs at this address,
        // and makes the USER_SCRIPT world's `chrome`.
        let start = InjectedScript.call("user-script", arguments: ["includeGlobs", "excludeGlobs", "userWorld"])
        let text = """
            /* Mote: a user script (chrome.userScripts) */
            mote_user_script: {
              const __moteStart = ((includeGlobs, excludeGlobs, userWorld) => {
            \(start)
              })(\(include), \(exclude), \(userWorld));
              if (!__moteStart) break mote_user_script;
            \(userWorld ? "const chrome = __moteStart.chrome;\nconst browser = chrome;" : "")
            \(code)
            }
            """
        let name = "us-" + SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined() + ".js"
        let own = folder.appendingPathComponent(UserScripts.folder, isDirectory: true)
        try FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
        let file = own.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: file.path) { try text.write(to: file, atomically: true, encoding: .utf8) }
        return UserScripts.folder + "/" + name
    }

    /// As JSON, for the script to read.
    private static func globs(_ script: [String: Any], _ property: String) throws -> String {
        guard let globs = ChromeAPIRules.globs(script[property]) else { throw InvalidUserScript(property: property) }
        return String(decoding: try JSONEncoder().encode(globs), as: UTF8.self)
    }
}

@available(macOS 15.4, *)
enum UserScripts {
    /// Mote's folder inside the extension.
    static let folder = "_mote"

    static func list(of id: String) -> URL { Extensions.folder(for: id).appendingPathComponent(folder + "/userscripts.json") }
    static func worlds(of id: String) -> URL { Extensions.folder(for: id).appendingPathComponent(folder + "/worlds.json") }

    static func read(_ file: URL) -> Any? { (try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) } }

    static func write(_ value: Any, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: value).write(to: file, options: .atomic)
    }

    /// Files no script uses any more, unless written in the last minute:
    /// one may be about to be injected.
    static func sweep(_ id: String, keeping used: Set<String>) {
        let own = Extensions.folder(for: id).appendingPathComponent(folder, isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: own, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where file.lastPathComponent.hasPrefix("us-") && !used.contains(file.lastPathComponent) {
            let written = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if -(written?.timeIntervalSinceNow ?? -999) > 60 { try? FileManager.default.removeItem(at: file) }
        }
    }
}

@available(macOS 15.4, *)
extension ChromeAPI {
    static func userScripts(_ call: ChromeCall) async throws -> Any? {
        let id = call.id
        let folder = Extensions.folder(for: id)
        switch call.method {
        case "file":
            return try ExtensionShims.userScriptFile(call.options, in: folder)
        case "list":
            return UserScripts.read(UserScripts.list(of: id)) ?? []
        case "save":
            let scripts = call.first as? [[String: Any]] ?? []
            try UserScripts.write(scripts, to: UserScripts.list(of: id))
            let used = scripts.compactMap { try? ExtensionShims.userScriptFile($0, in: folder) }.map { ($0 as NSString).lastPathComponent }
            UserScripts.sweep(id, keeping: Set(used))
            return nil
        case "worlds":
            return UserScripts.read(UserScripts.worlds(of: id)) as? [[String: Any]] ?? []
        case "world":
            let world: String = call.option("worldId") ?? ""
            var worlds = (UserScripts.read(UserScripts.worlds(of: id)) as? [[String: Any]] ?? []).filter {
                ($0["worldId"] as? String ?? "") != world
            }
            if call.option("reset") != true { worlds.append(call.options) }
            try UserScripts.write(worlds, to: UserScripts.worlds(of: id))
            return nil
        default:
            throw unavailable(call)
        }
    }
}
