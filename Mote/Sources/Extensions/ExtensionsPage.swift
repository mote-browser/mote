import Combine
import MoteCore
import SwiftUI
import WebKit

/// Settings › Extensions: adding from the Chrome Web Store or a folder, and
/// every installed extension.
struct ExtensionsPage: View {
    @ObservedObject var browser: Browser

    var body: some View {
        if #available(macOS 15.4, *) {
            InstalledList(browser: browser, extensions: .shared)
        } else {
            SettingsSection {
                SettingRow(
                    "Chrome extensions", "They need macOS 15.4 or later, whose WebKit can run them", symbol: "puzzlepiece.extension",
                    tint: Tint.gray
                ) {
                    EmptyView()
                }
            }
        }
    }
}

@available(macOS 15.4, *)
private struct InstalledList: View {
    @ObservedObject var browser: Browser
    @ObservedObject var extensions: Extensions

    var body: some View {
        StoreSection(browser: browser, extensions: extensions)

        SettingsSection("Installed") {
            if extensions.installed.isEmpty {
                Text("Nothing yet. Extensions you add show up here.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
            ForEach(Array(extensions.installed.enumerated()), id: \.element.id) { index, item in
                if index > 0 { RowRule() }
                ExtensionRow(item: item, extensions: extensions)
            }
        }

        SettingsSection("Where they run") {
            SettingRow(
                "In private tabs too", "Off at first: a private tab keeps nothing, extensions included", symbol: "eyeglasses",
                tint: Tint.indigo
            ) {
                Switch(on: Binding(get: { browser.prefs.extensionsInPrivate }, set: { browser.prefs.extensionsInPrivate = $0 }))
            }
        }

        SettingsSection("Your own", note: "Reload picks up what you've changed in the folder since.") {
            SettingRow(
                "Load from a folder", "One with a manifest.json: yours, or one taken out of another browser", symbol: "folder.badge.plus",
                tint: Tint.blue
            ) {
                Pill("Choose…") { extensions.installFolder() }
            }
        }
    }
}

/// Adding one by its store link or id.
@available(macOS 15.4, *)
private struct StoreSection: View {
    @ObservedObject var browser: Browser
    @ObservedObject var extensions: Extensions
    @State private var link = ""

    private var valid: Bool { CRX.extensionID(in: link) != nil }

    var body: some View {
        SettingsSection("From the Chrome Web Store", note: "Or find one in the store and press Add to Mote on its page.") {
            SettingRow("Browse the store", "Extensions made for Chrome run here too", symbol: "bag", tint: Tint.purple) {
                Pill("Open") {
                    browser.tuning = false
                    browser.open(Browser.webStore, foreground: true)
                }
            }
            RowRule()
            HStack(spacing: 8) {
                TextField("", text: $link)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Palette.ink)
                    .onSubmit(add)
                    .background(alignment: .leading) {
                        if link.isEmpty { Text("Paste a store link or an extension id").foregroundStyle(Palette.muted.opacity(0.8)) }
                    }
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Palette.ground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                if extensions.busy != nil {
                    Ring(size: 12)
                } else {
                    Pill("Add", filled: true, action: add).disabled(!valid)
                }
            }
            .padding(EdgeInsets(top: 9, leading: 47, bottom: 10, trailing: 12))
        }
    }

    private func add() {
        guard valid else { return }
        extensions.install(from: link)
        link = ""
    }
}

@available(macOS 15.4, *)
private struct ExtensionRow: View {
    let item: Installed
    @ObservedObject var extensions: Extensions
    @State private var hovering = false

    private var context: WKWebExtensionContext? { extensions.contexts[item.id] }
    private var hasNewTabPage: Bool { context?.overrideNewTabPageURL != nil }
    private var inNewTabs: Bool { hasNewTabPage && extensions.showsInNewTabs(item.id) == true }

    var body: some View {
        HStack(spacing: 11) {
            icon.frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.system(size: 13)).foregroundStyle(Palette.ink).lineLimit(1)
                Text(ExtensionRules.detail(item, running: context != nil, showsInNewTabs: inNewTabs, warnings: context?.errors.count ?? 0))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .help(item.source ?? "")
            }
            Spacer(minLength: 8)
            if hovering { actions }
            Switch(on: Binding(get: { item.enabled }, set: { extensions.setEnabled(item.id, $0) }))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var icon: some View {
        if let image = context?.webExtension.icon(for: CGSize(width: 48, height: 48)) {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            SymbolTile(symbol: "puzzlepiece.extension", tint: Tint.gray)
        }
    }

    @ViewBuilder private var actions: some View {
        let pinned = item.pinned ?? false
        Quick(pinned ? "Unpin" : "Pin") { extensions.setPinned(item.id, !pinned) }
        if hasNewTabPage {
            Quick(inNewTabs ? "Not in New Tabs" : "In New Tabs") { extensions.setShowsInNewTabs(item.id, !inNewTabs) }
        }
        if item.source != nil || !item.fromStore { Quick("Reload") { extensions.reload(item.id) } }
        if context?.optionsPageURL != nil { Quick("Options") { extensions.openOptions(item.id) } }
        Quick("Remove", tint: .red.opacity(0.75)) { extensions.remove(item.id) }
    }
}

/// On a store page whose "Add to Mote" button couldn't be put in (the
/// store's markup changed, say), an offer at the bottom instead.
struct StoreOffer: View {
    @ObservedObject var browser: Browser

    var body: some View {
        if #available(macOS 15.4, *), let tab = browser.active { OfferBubble(tab: tab, extensions: .shared) }
    }
}

@available(macOS 15.4, *)
private struct OfferBubble: View {
    @ObservedObject var tab: Tab
    @ObservedObject var extensions: Extensions

    /// The extension this page offers, when the page's own button isn't there
    /// and it isn't installed yet.
    private var offered: String? {
        guard let page = tab.address, ExtensionRules.isStorePage(page), let id = CRX.extensionID(in: page.absoluteString),
            tab.storePlaced != id, !extensions.installed.contains(where: { $0.id == id })
        else { return nil }
        return id
    }

    var body: some View {
        if let id = offered {
            let adding = extensions.busy == id
            HStack(spacing: 12) {
                Image(systemName: "puzzlepiece.extension").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
                Text(adding ? "Adding…" : "Add this extension to Mote").font(.system(size: 12.5)).foregroundStyle(Palette.ink)
                if adding {
                    Ring(size: 10)
                } else {
                    Button("Add") { extensions.install(from: id) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.ground)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(Palette.ink, in: Capsule())
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .padding(.vertical, 9)
            .background(Palette.ground, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 20, y: 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
