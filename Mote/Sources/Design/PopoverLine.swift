import SwiftUI

/// A line at the foot of a toolbar menu (bookmarks, extensions): an optional
/// symbol, then its title, washed on hover. Titles line up with or without
/// a symbol.
struct PopoverLine: View {
    let title: String
    var symbol: String?
    let act: () -> Void
    @State private var hovering = false

    init(_ title: String, symbol: String? = nil, act: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.act = act
    }

    var body: some View {
        HStack(spacing: 8) {
            // An empty Group with a frame would collapse; the clear colour keeps the room.
            ZStack {
                Color.clear
                if let symbol { Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(Palette.muted) }
            }
            .frame(width: 14, height: 14)
            Text(title).font(.system(size: 12.5)).foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(hovering ? Palette.wash : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: act)
        .onHover { hovering = $0 }
    }
}
