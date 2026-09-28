import MoteCore
import SwiftUI
import WebKit

/// Site icons. WebKit doesn't hand them over, so the page is asked what it
/// declares, the best candidate (see IconChoice) is downloaded once and kept
/// as a 64 px PNG in the profile's icons folder. Dark-mode variants are kept
/// apart as "<host>@dark".
@MainActor
final class Favicons {
    static let shared = Favicons()

    /// Hears each icon that arrives, so every tab on its site can take it.
    var arrived: ((String, NSImage) -> Void)?

    private let files = IconFiles()
    private var loaded: [String: NSImage] = [:]
    /// Names known to have no file, so long lists don't ask the disk per row.
    private var unfiled: Set<String> = []
    /// Sites being fetched, and sites with no icon to be had this session.
    private var fetching: Set<String> = []
    private var iconless: Set<String> = []
    /// Icons looked up for sites with no tab open (see `icon(for:)`), shared by all who ask.
    private var lookups: [String: Task<NSImage?, Never>] = [:]

    static var dark: Bool { NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }

    private static func name(_ host: String, dark: Bool) -> String { dark ? host + "@dark" : host }

    /// A site's icon if one is kept, without fetching: the dark one in dark
    /// mode when there is one.
    func cached(_ host: String) -> NSImage? {
        (Self.dark ? image(Self.name(host, dark: true)) : nil) ?? image(host)
    }

    private func image(_ name: String) -> NSImage? {
        if let image = loaded[name] { return image }
        guard !unfiled.contains(name) else { return nil }
        guard let image = files.read(name) else {
            unfiled.insert(name)
            return nil
        }
        loaded[name] = image
        return image
    }

    private func keep(_ image: NSImage, as name: String, host: String, onDisk: Bool) {
        loaded[name] = image
        if onDisk { files.write(image, as: name) }
        arrived?(host, image)
    }

    /// After the appearance changes: the icons on hand now, then a fetch
    /// where the new appearance may have its own.
    func relook(_ tabs: [Tab]) {
        iconless = []
        for tab in tabs {
            guard let host = tab.address?.host()?.lowercased() else { continue }
            tab.icon = cached(host)
            fetch(for: tab)
        }
    }

    /// An icon from elsewhere (another browser's import), unless the site has one.
    func adopt(_ data: Data, for host: String) async {
        guard cached(host) == nil, let image = await Self.square(data) else { return }
        keep(image, as: host, host: host, onDisk: true)
    }

    /// Asks the page for its icons and downloads the best, unless a recent
    /// one is kept. In dark mode a recent light icon isn't enough: the site
    /// may have a dark one not fetched yet.
    func fetch(for tab: Tab) {
        guard let page = tab.address, let host = page.host()?.lowercased(), page.scheme?.hasPrefix("http") == true else { return }
        let dark = Self.dark
        if let kept = recent(Self.name(host, dark: dark)) {
            tab.icon = kept
            return
        }
        guard !fetching.contains(host), !iconless.contains(host) else { return }
        fetching.insert(host)

        tab.web.callAsyncJavaScript(Self.probe, arguments: [:], in: nil, in: .page) { [weak self, weak tab] result in
            guard let self else { return }
            let declared = ((try? result.get()) as? [[String: String]] ?? []).compactMap(IconChoice.Declared.init)
            let wantsDark = dark && IconChoice.offersDark(declared)
            let name = Self.name(host, dark: wantsDark)
            // No dark variant, and the plain icon is recent.
            if !wantsDark, let kept = recent(name) {
                tab?.icon = kept
                fetching.remove(host)
                return
            }
            let candidates = IconChoice.candidates(declared, page: page, dark: wantsDark)
            // A private tab's icons aren't written down.
            let onDisk = !(tab?.shy ?? false)
            Task { await self.download(candidates, host: host, as: name, onDisk: onDisk) }
        }
    }

    /// A site's icon with no page of it open, as for a chat's sources: the
    /// kept one, or else its /favicon.ico, held in memory only. Kept apart
    /// from tabs' fetching, so a miss here never stops a tab finding the
    /// icon its page declares.
    func icon(for host: String) async -> NSImage? {
        if let kept = cached(host) { return kept }
        if let asking = lookups[host] { return await asking.value }
        guard let root = URL(string: "https://\(host)") else { return nil }
        let asking = Task { @MainActor [weak self] () -> NSImage? in
            for url in [root.appending(path: "favicon.ico"), root.appending(path: "apple-touch-icon.png")] {
                guard let (data, response) = try? await Self.session.data(from: url),
                    (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                    (61..<2_000_000).contains(data.count), let image = await Self.square(data)
                else { continue }
                self?.loaded[host] = image
                return image
            }
            return nil
        }
        lookups[host] = asking
        return await asking.value
    }

    /// The kept icon if it is less than a week old.
    private func recent(_ name: String) -> NSImage? {
        files.fresh(name) ? image(name) : nil
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        return URLSession(configuration: configuration)
    }()

    private func download(_ candidates: [URL], host: String, as name: String, onDisk: Bool) async {
        defer { fetching.remove(host) }
        for url in candidates {
            guard let (data, response) = try? await Self.session.data(from: url),
                (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                (61..<2_000_000).contains(data.count), let image = await Self.square(data)
            else { continue }
            return keep(image, as: name, host: host, onDisk: onDisk)
        }
        iconless.insert(host)
    }

    /// Decodes and fits an image into a 64-point square, drawn at twice that
    /// for Retina, off the main thread: an .ico can hold many sizes and be
    /// slow to decode.
    private static func square(_ data: Data) async -> NSImage? {
        await Task.detached(priority: .utility) { () -> NSImage? in
            guard let image = NSImage(data: data), image.isValid, image.size.width > 0, image.size.height > 0,
                let bitmap = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
            else { return nil }
            let side: CGFloat = 64
            bitmap.size = NSSize(width: side, height: side)
            let scale = min(side / image.size.width, side / image.size.height)
            let fitted = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(in: NSRect(origin: NSPoint(x: (side - fitted.width) / 2, y: (side - fitted.height) / 2), size: fitted))
            NSGraphicsContext.restoreGraphicsState()
            let square = NSImage(size: bitmap.size)
            square.addRepresentation(bitmap)
            return square
        }.value
    }

    /// The icons the page declares (href, rel, sizes, type, media), lowercased.
    /// See Scripts/src/favicon-probe.ts.
    private static let probe = InjectedScript.call("favicon-probe")
}

/// The icons folder: one PNG per site and appearance.
private struct IconFiles {
    private let folder = Storage.folder.appending(path: "icons", directoryHint: .isDirectory)
    private let writer = DispatchQueue(label: "io.github.mote-browser.icons", qos: .utility)

    private func file(_ name: String) -> URL { folder.appending(path: name + ".png") }

    func read(_ name: String) -> NSImage? { NSImage(contentsOf: file(name)) }

    /// Written within the last week.
    func fresh(_ name: String) -> Bool {
        guard let written = try? file(name).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
            return false
        }
        return Date().timeIntervalSince(written) < 7 * 86_400
    }

    func write(_ image: NSImage, as name: String) {
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        let folder = folder
        let file = file(name)
        writer.async {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? png.write(to: file, options: .atomic)
        }
    }
}
