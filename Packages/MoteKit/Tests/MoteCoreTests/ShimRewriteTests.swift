import Foundation
import Testing

@testable import MoteCore

@Suite("ShimRewrite")
struct ShimRewriteTests {
    @Test("The manifest gains nativeMessaging, and scripting for userScripts, noting what was added")
    func permissions() {
        let plain = ShimRewrite.manifest(["permissions": ["tabs"]], added: [])
        #expect(plain.manifest["permissions"] as? [String] == ["tabs", "nativeMessaging"])
        #expect(plain.added == ["nativeMessaging"])
        let users = ShimRewrite.manifest(["permissions": ["userScripts", "nativeMessaging"]], added: ["nativeMessaging"])
        #expect(users.manifest["permissions"] as? [String] == ["userScripts", "nativeMessaging", "scripting"])
        #expect(users.added == ["nativeMessaging", "scripting"])
    }

    @Test("The shim goes first among background and content scripts; the passkey patch before MAIN ones")
    func scripts() {
        let manifest: [String: Any] = [
            "background": ["scripts": ["a.js"], "service_worker": "w.js"],
            "content_scripts": [["js": ["c.js"]], ["js": ["m.js"], "world": "main"], ["css": ["x.css"]]],
        ]
        let once = ShimRewrite.manifest(manifest, added: []).manifest
        let twice = ShimRewrite.manifest(once, added: []).manifest
        for result in [once, twice] {
            #expect((result["background"] as? [String: Any])?["scripts"] as? [String] == ["mote-shim.js", "a.js"])
            let content = result["content_scripts"] as? [[String: Any]]
            #expect(content?[0]["js"] as? [String] == ["mote-shim.js", "c.js"])
            #expect(content?[1]["js"] as? [String] == ["mote-passkeys.js", "mote-shim.js", "m.js"])
            #expect(content?[2]["js"] == nil)
        }
        #expect(ShimRewrite.worker(in: once)?.path == "w.js")
        #expect(ShimRewrite.worker(in: ["background": ["service_worker": "m.js", "type": "module"]])?.module == true)
    }

    @Test("Workers get the shim written in or imported, once, however often they're prepared")
    func workers() {
        let classic = ShimRewrite.worker("run();\n", shim: "SHIM", module: false)
        #expect(classic == ShimRewrite.marker + "\nSHIM\n" + ShimRewrite.ender + "\nrun();\n")
        #expect(
            ShimRewrite.worker(classic, shim: "NEW", module: false) == ShimRewrite.marker + "\nNEW\n" + ShimRewrite.ender + "\nrun();\n")
        let module = ShimRewrite.worker("run();\n", shim: "SHIM", module: true)
        #expect(module == "import \"/mote-shim.js\";\nrun();\n")
        #expect(ShimRewrite.worker(module, shim: "SHIM", module: true) == module)
        let legacy = ShimRewrite.marker + "\n(() => {\n})();\nrun();\n"
        #expect(ShimRewrite.withoutShim(legacy) == "run();\n")
    }

    @Test("Pages get the script tag in their head, once")
    func pages() {
        let page = ShimRewrite.page("<html><HEAD lang=x><title>t</title></head></html>")
        #expect(page == "<html><HEAD lang=x><script src=\"/mote-shim.js\"></script><title>t</title></head></html>")
        #expect(ShimRewrite.page(page!) == nil)
        #expect(ShimRewrite.page("<p>no head</p>") == "<script src=\"/mote-shim.js\"></script><p>no head</p>")
    }

    @Test("Events mentioned in a script are found, outside any shim written in")
    func events() {
        let script = "chrome.tabs.onUpdated.addListener(f); browser.runtime.onMessage; x.notAnEvent; chrome.alarms.onalarm"
        #expect(ShimRewrite.events(in: script) == ["tabs.onUpdated", "runtime.onMessage"])
        let written = ShimRewrite.marker + "\nchrome.storage.onChanged\n" + ShimRewrite.ender + "\nchrome.idle.onStateChanged"
        #expect(ShimRewrite.events(in: written) == ["idle.onStateChanged"])
    }

    @Test("The script list has Mote's files, marks empty ones and is sorted")
    func scriptList() {
        let list = ShimRewrite.scriptList([("/worker.js", false), ("/mote-shim.js", false), ("/empty.js", true)])
        #expect(list == ["-/empty.js", "/mote-passkeys.js", "/mote-shim.js", "/worker.js"])
    }
}
