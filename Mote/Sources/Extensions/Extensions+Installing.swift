import AppKit
import MoteCore
import WebKit

// Adding, reloading, updating and removing extensions. Each new copy is
// unpacked beside the others as ".staging-<id>", read, agreed to, and only
// then moved into place; a copy nobody agreed to is thrown away.

@available(macOS 15.4, *)
extension Extensions {
    private static func staging(_ id: String) -> URL {
        folder.appendingPathComponent(".staging-\(id)", isDirectory: true)
    }

    /// A folder's extension, copied beside the others with this build's shim.
    private static func stage(copying source: URL, as id: String) throws -> URL {
        let files = FileManager.default
        let staged = staging(id)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        try? files.removeItem(at: staged)
        do {
            try files.copyItem(at: source, to: staged)
            try ExtensionShims.prepare(staged, fresh: true)
        } catch {
            try? files.removeItem(at: staged)
            throw error
        }
        return staged
    }

    /// The store's latest, verified, unpacked beside the others with the shim.
    private static func stage(fromStore id: String) async throws -> URL {
        let archive = try CRX.verifiedArchive(try await CRX.download(id), extensionID: id)
        let staged = staging(id)
        try CRX.unpack(archive, into: staged)
        try ExtensionShims.prepare(staged, fresh: true)
        return staged
    }

    private static func putInPlace(_ staged: URL, as id: String) throws {
        let target = folder(for: id)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: staged, to: target)
    }

    private static func hasManifest(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent("manifest.json").path)
    }

    /// Tells the person, in the browser's notice.
    func say(_ text: String) { browser?.announce(text) }

    // MARK: - Adding

    /// From a Chrome Web Store link or id. `confirm: false` skips the question
    /// in test runs only.
    func install(from text: String, confirm: Bool = true) {
        guard let id = CRX.extensionID(in: text) else { return say(CRX.Failure.notAnExtensionID.localizedDescription) }
        guard index(of: id) == nil else { return say("Already installed") }
        busy = id
        Task {
            defer { busy = nil }
            do {
                try await admit(try await Self.stage(fromStore: id), as: id, fromStore: true, confirm: confirm || !Storage.testing)
            } catch {
                say(error.localizedDescription)
            }
        }
    }

    /// Asks for an unpacked extension's folder.
    func installFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Load Extension"
        panel.message = "Choose the folder that holds the extension's manifest.json."
        guard panel.runModal() == .OK, let source = panel.url else { return }
        installFolder(at: source)
    }

    /// Copied in, so the folder can move; Reload copies it again.
    func installFolder(at source: URL, confirm: Bool = true) {
        guard Self.hasManifest(source) else { return say("That folder has no manifest.json") }
        let id = Installed.localID()
        guard let staged = try? Self.stage(copying: source, as: id) else { return say("Couldn't copy the extension") }
        Task { try? await admit(staged, as: id, fromStore: false, confirm: confirm || !Storage.testing, source: source) }
    }

    /// Asks about a staged extension, then puts it in place and starts it.
    private func admit(_ staged: URL, as id: String, fromStore: Bool, confirm: Bool, source: URL? = nil) async throws {
        let found: WKWebExtension
        do {
            found = try await WKWebExtension(resourceBaseURL: staged)
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw error
        }
        let name = found.displayName ?? id
        let agreed = confirm ? await ask(install: name, wants: Self.describe(found, in: staged), icon: Self.icon(of: found)) : true
        guard agreed else {
            try? FileManager.default.removeItem(at: staged)
            return
        }
        try Self.putInPlace(staged, as: id)
        let item = Installed(
            id: id, name: name, version: found.version ?? "?", fromStore: fromStore,
            permissions: Self.grants(found, in: Self.folder(for: id)),
            source: source?.path)
        installed.removeAll { $0.id == id }
        installed.append(item)
        save()
        say(await load(item) ? "\(name) is installed" : "\(name) is installed, but WebKit couldn't start it")
    }

    // MARK: - Reloading

    /// As Chrome's developer mode does; an unpacked one is copied from its
    /// folder again first.
    func reload(_ id: String) {
        guard let item = installed.first(where: { $0.id == id }), reloading.insert(id).inserted else { return }
        var staged: URL?
        if let path = item.source {
            let source = URL(fileURLWithPath: path, isDirectory: true)
            guard Self.hasManifest(source) else {
                reloading.remove(id)
                return say("The folder \(item.name) was loaded from is gone")
            }
            guard let copy = try? Self.stage(copying: source, as: id) else {
                reloading.remove(id)
                return say("Couldn't copy \(item.name) again")
            }
            staged = copy
        }
        Task {
            defer { reloading.remove(id) }
            await reload(item, from: staged)
        }
    }

    private func reload(_ item: Installed, from staged: URL?) async {
        let id = item.id
        let read = staged ?? Self.folder(for: id)
        let found = try? await WKWebExtension(resourceBaseURL: read)
        let discard = { if let staged { try? FileManager.default.removeItem(at: staged) } }
        if found == nil, staged != nil {
            discard()
            return say("\(item.name) wasn't reloaded — its manifest couldn't be read")
        }
        if let found, ExtensionRules.wantsMore(Self.grants(found, in: read), than: item.permissions) {
            let name = [found.displayName ?? item.name, found.version].compactMap { $0 }.joined(separator: " ")
            guard await ask(install: name, wants: Self.describe(found, in: read), icon: Self.icon(of: found)) else {
                discard()
                return say("\(item.name) wasn't reloaded — it asks for more than before")
            }
        }
        unload(id)
        forgetErrors(of: id)
        if let staged {
            do {
                try Self.putInPlace(staged, as: id)
            } catch {
                discard()
                return say("Couldn't copy \(item.name) again")
            }
        }
        if let found, let at = index(of: id) {
            installed[at].name = found.displayName ?? installed[at].name
            installed[at].version = found.version ?? installed[at].version
            installed[at].permissions = Self.grants(found, in: Self.folder(for: id))
            save()
        }
        guard let now = installed.first(where: { $0.id == id }), now.enabled else { return }
        say(await load(now) ? "\(now.name) reloaded" : "\(now.name) couldn't start — see Settings › Extensions")
    }

    // MARK: - Updates

    /// The store is asked at most every 20 hours; an update that wants more
    /// asks first.
    func checkForUpdates() {
        let key = "extensions.checked"
        let last = Storage.settings.object(forKey: key) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > ExtensionRules.updateInterval else { return }
        Storage.settings.set(Date(), forKey: key)
        for item in installed where item.fromStore {
            Task { await update(item) }
        }
    }

    private func update(_ item: Installed) async {
        guard let check = ExtensionRules.updateCheckURL(id: item.id, version: item.version),
            let (data, _) = try? await URLSession.shared.data(from: check),
            let offered = ExtensionRules.offeredVersion(in: String(decoding: data, as: UTF8.self), current: item.version)
        else { return }
        do {
            let staged = try await Self.stage(fromStore: item.id)
            let found = try await WKWebExtension(resourceBaseURL: staged)
            // Sites count too, against what was agreed to.
            let grants = Self.grants(found, in: staged)
            if ExtensionRules.wantsMore(grants, than: item.permissions) {
                guard await ask(install: "An update to \(item.name)", wants: Self.describe(found, in: staged), icon: Self.icon(of: found))
                else {
                    try? FileManager.default.removeItem(at: staged)
                    return
                }
            }
            unload(item.id)
            try Self.putInPlace(staged, as: item.id)
            guard let at = index(of: item.id) else { return }
            installed[at].version = found.version ?? offered
            installed[at].permissions = grants
            save()
            if installed[at].enabled { await load(installed[at]) }
        } catch {
            NSLog("Extensions: update of %@ failed: %@", item.id, error.localizedDescription)
        }
    }

    // MARK: - Switches

    func setEnabled(_ id: String, _ on: Bool) {
        guard let at = index(of: id) else { return }
        installed[at].enabled = on
        save()
        if on {
            let item = installed[at]
            Task { await load(item) }
        } else {
            unload(id)
        }
    }

    func setPinned(_ id: String, _ on: Bool) {
        guard let at = index(of: id) else { return }
        installed[at].pinned = on
        save()
        actionsChanged += 1
    }

    func openOptions(_ id: String) {
        guard let page = contexts[id]?.optionsPageURL else { return }
        browser?.open(page, foreground: true)
    }

    /// With its settings, its answers and its files.
    func remove(_ id: String) {
        unload(id)
        forgetErrors(of: id)
        forgetLoads(of: id)
        Self.setSettings([:], for: id)
        for key in ["extensions.granted.\(id)", Self.newTabKey(id)] { Storage.settings.removeObject(forKey: key) }
        installed.removeAll { $0.id == id }
        save()
        try? FileManager.default.removeItem(at: Self.folder(for: id))
    }
}
