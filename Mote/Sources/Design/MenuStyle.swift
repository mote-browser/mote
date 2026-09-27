import AppKit
import SwiftUI

/// The measurements of a native menu (taken from `NSMenu.size`), so views
/// that act as menus look like the tab's context menu.
enum MenuMetrics {
    static let font = Font(NSFont.menuFont(ofSize: 0))
    static let row: CGFloat = 24
    static let separator: CGFloat = 11
    /// Above the first item and below the last.
    static let pad: CGFloat = 5
    /// The highlight's inset from the menu's edges.
    static let inset: CGFloat = 5
    /// Text from the menu's edge, in a menu without a checkmark column.
    static let text: CGFloat = 17
    /// From the text or shortcut to the menu's trailing edge.
    static let trailing: CGFloat = 17
    /// A separator line's inset from each side.
    static let rule: CGFloat = 16
    static let highlight: CGFloat = 6
    static let corner: CGFloat = 12

    /// The hover highlight: the accent colour as it looks on menu material,
    /// lighter than the plain accent.
    static let selection = Color(
        nsColor: NSColor(name: nil) { appearance in
            let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return (dark ? accent.blended(withFraction: 0.15, of: .black) : accent.blended(withFraction: 0.42, of: .white)) ?? accent
        })

    /// The outline of a menu's panel.
    static let edge = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .white.withAlphaComponent(0.18) : .black.withAlphaComponent(0.26)
    }
}

/// An item in a menu-looking view: a title, maybe a shortcut or a submenu arrow.
struct MenuRow: View {
    let title: String
    var keys = ""
    var submenu = false
    let act: () -> Void

    @State private var hovering = false

    init(_ title: String, keys: String = "", submenu: Bool = false, act: @escaping () -> Void) {
        self.title = title
        self.keys = keys
        self.submenu = submenu
        self.act = act
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(title).foregroundStyle(hovering ? .white : Color(nsColor: .labelColor)).lineLimit(1).fixedSize()
            Spacer(minLength: keys.isEmpty ? 24 : 26)
            Group {
                if !keys.isEmpty { Text(keys).fixedSize() }
                if submenu { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)) }
            }
            .foregroundStyle(hovering ? .white : Color(nsColor: .secondaryLabelColor))
        }
        .font(MenuMetrics.font)
        .padding(.leading, MenuMetrics.text - MenuMetrics.inset)
        .padding(.trailing, MenuMetrics.trailing - MenuMetrics.inset)
        .frame(height: MenuMetrics.row)
        .background(
            hovering ? MenuMetrics.selection : .clear, in: RoundedRectangle(cornerRadius: MenuMetrics.highlight, style: .continuous)
        )
        .padding(.horizontal, MenuMetrics.inset)
        .contentShape(Rectangle())
        .onTapGesture(perform: act)
        .onHover { hovering = $0 }
    }
}

/// A menu's section heading.
struct MenuHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .lineLimit(1)
            .padding(.leading, MenuMetrics.text)
            .padding(.trailing, MenuMetrics.trailing)
            .frame(height: MenuMetrics.row, alignment: .leading)
    }
}

struct MenuSeparator: View {
    var body: some View {
        Color(nsColor: .separatorColor).frame(height: 1).padding(.horizontal, MenuMetrics.rule).frame(height: MenuMetrics.separator)
    }
}
