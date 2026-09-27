import AppKit
import MoteCore
import SwiftUI
import WebKit

// Extensions in the toolbar: the pinned ones' buttons, then the puzzle
// button with every extension in its menu. Nothing before macOS 15.4, or
// with nothing installed.

struct ExtensionSlot: View {
    /// Where the menu opens from.
    var edge: Edge = .bottom

    var body: some View {
        if #available(macOS 15.4, *) { ExtensionBar(extensions: .shared, edge: edge) }
    }
}

@available(macOS 15.4, *)
private struct ExtensionBar: View {
    @ObservedObject var extensions: Extensions
    let edge: Edge

    var body: some View {
        if !extensions.installed.isEmpty {
            HStack(spacing: 2) {
                ForEach(extensions.buttons.filter(\.pinned)) { button in
                    PinnedButton(button: button) { extensions.press(button.id) }
                        .background(PopupAnchor(id: button.id))
                        .contextMenu { ExtensionActions(id: button.id, name: button.name, extensions: extensions) }
                }
                Door(icon: "puzzlepiece.extension", on: extensions.menuOpen, help: "Extensions") { extensions.menuOpen.toggle() }
                    .background(PopupAnchor(id: Extensions.menuAnchor))
                    .menuPanel(isPresented: $extensions.menuOpen, edge: edge) { ExtensionMenu(extensions: extensions) }
            }
        }
    }
}

@available(macOS 15.4, *)
private struct PinnedButton: View {
    let button: Extensions.Button
    let press: () -> Void
    @State private var hovering = false
    private let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

    var body: some View {
        Button(action: press) {
            ExtensionIcon(button: button, size: 15)
                .frame(width: 26, height: 26)
                .background(hovering ? Palette.hover : .clear, in: shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(button.label)
    }
}

/// Tells Extensions which view a popup hangs from.
@available(macOS 15.4, *)
private struct PopupAnchor: NSViewRepresentable {
    let id: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Extensions.shared.anchors[id] = WeakView(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        Extensions.shared.anchors[id] = WeakView(view)
    }
}

/// Its icon with its badge; without an icon, its initial, so it isn't
/// taken for the puzzle button.
@available(macOS 15.4, *)
private struct ExtensionIcon: View {
    let button: Extensions.Button
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            picture
                .frame(width: size + 4, height: size + 4)
                .opacity(button.enabled ? 1 : 0.4)
            if !button.badge.isEmpty {
                Text(button.badge)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Palette.ground)
                    .padding(.horizontal, 3)
                    .frame(minWidth: 12, minHeight: 11)
                    .background(Palette.ink, in: Capsule())
                    .fixedSize()
                    .offset(x: 5, y: 3)
            }
        }
    }

    @ViewBuilder private var picture: some View {
        if let icon = button.icon {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Text(button.name.first.map { String($0).uppercased() } ?? "?")
                .font(.system(size: size * 0.62, weight: .semibold))
                .foregroundStyle(Palette.muted)
                .frame(width: size, height: size)
                .background(Palette.wash, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        }
    }
}

/// An extension's context menu.
@available(macOS 15.4, *)
private struct ExtensionActions: View {
    let id: String
    let name: String
    let extensions: Extensions

    var body: some View {
        let pinned = extensions.installed.first { $0.id == id }?.pinned ?? false
        Button(pinned ? "Unpin" : "Pin to Toolbar") { extensions.setPinned(id, !pinned) }
        if extensions.contexts[id]?.optionsPageURL != nil { Button("Options…") { extensions.openOptions(id) } }
        Button("Reload") { extensions.reload(id) }
        Divider()
        Button("Remove “\(name)”…") {
            let alert = Dialogs.alert("Remove “\(name)”?", "Its settings and data go with it.", buttons: ["Remove", "Cancel"])
            if alert.runModal() == .alertFirstButtonReturn { extensions.remove(id) }
        }
    }
}

/// The puzzle button's menu, drawn off screen for the bench: a popover
/// can't stay open while the browser is in the background.
@available(macOS 15.4, *)
@MainActor
func extensionMenuPicture() -> NSBitmapImageRep? {
    let host = NSHostingView(rootView: ExtensionMenu(extensions: .shared))
    host.frame = NSRect(origin: .zero, size: host.fittingSize)
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.appearance = NSApp.effectiveAppearance
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    guard let picture = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
    host.cacheDisplay(in: host.bounds, to: picture)
    return picture
}

/// The puzzle button's menu: every running extension, then the store,
/// loading a folder, and Settings.
@available(macOS 15.4, *)
private struct ExtensionMenu: View {
    @ObservedObject var extensions: Extensions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let buttons = extensions.buttons
            if buttons.isEmpty {
                Text("None of your extensions is on").font(.system(size: 12.5)).foregroundStyle(Palette.muted).padding(14)
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(buttons) { ExtensionLine(button: $0, extensions: extensions) }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 360)
                .fixedSize(horizontal: false, vertical: true)
            }
            Divider().overlay(Palette.hairline)
            VStack(spacing: 1) {
                PopoverLine("Chrome Web Store…", symbol: "storefront") {
                    closing { extensions.browser?.open(Browser.webStore, foreground: true) }
                }
                PopoverLine("Load Unpacked…", symbol: "folder") { closing { DispatchQueue.main.async { extensions.installFolder() } } }
                PopoverLine("Manage Extensions…", symbol: "gearshape") {
                    closing {
                        Storage.settings.set("extensions", forKey: "settings.page")
                        extensions.browser?.tuning = true
                    }
                }
            }
            .padding(6)
        }
        .frame(width: 280)
        .background(Palette.ground)
    }

    private func closing(_ then: () -> Void) {
        extensions.menuOpen = false
        then()
    }
}

@available(macOS 15.4, *)
private struct ExtensionLine: View {
    let button: Extensions.Button
    @ObservedObject var extensions: Extensions
    @State private var hovering = false

    private var fromFolder: Bool { extensions.installed.first { $0.id == button.id }?.source != nil }

    var body: some View {
        HStack(spacing: 9) {
            ExtensionIcon(button: button, size: 16)
            Text(button.name).font(.system(size: 12.5)).foregroundStyle(button.enabled ? Palette.ink : Palette.muted).lineLimit(1)
            Spacer(minLength: 4)
            if hovering, fromFolder {
                LineTool(symbol: "arrow.clockwise", help: "Reload from its folder") { extensions.reload(button.id) }
            }
            if hovering || button.pinned {
                LineTool(symbol: button.pinned ? "pin.fill" : "pin", help: button.pinned ? "Unpin" : "Pin to toolbar", on: button.pinned) {
                    extensions.setPinned(button.id, !button.pinned)
                }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: 30)
        .background(hovering ? Palette.wash : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            // The menu closes first, so the popup hangs from the puzzle button.
            extensions.menuOpen = false
            let id = button.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { extensions.press(id) }
        }
        .onHover { hovering = $0 }
        .help(button.label)
        .contextMenu { ExtensionActions(id: button.id, name: button.name, extensions: extensions) }
    }
}

private struct LineTool: View {
    let symbol: String
    let help: String
    var on = false
    let act: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(on || hovering ? Palette.ink : Palette.muted)
                .frame(width: 22, height: 22)
                .background(hovering ? Palette.hover : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
