import SwiftUI

// The pieces Settings is made of: the bar of pages along the top, and
// sections of rows, each row led by a coloured symbol.

/// The pages, side by side under the traffic lights.
struct SettingsPageBar: View {
    @Binding var page: SettingsPage

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SettingsPage.allCases) { item in
                PageButton(page: item, chosen: page == item) { withAnimation(Motion.quick) { page = item } }
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
    }

    private struct PageButton: View {
        let page: SettingsPage
        let chosen: Bool
        let pick: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: pick) {
                VStack(spacing: 4) {
                    Image(systemName: page.symbol)
                        .font(.system(size: 16, weight: .regular))
                        .symbolVariant(chosen ? .fill : .none)
                        .frame(height: 20)
                    Text(page.title).font(.system(size: 11, weight: chosen ? .semibold : .regular))
                }
                .foregroundStyle(chosen ? page.tint : hovering ? Palette.ink.opacity(0.8) : Palette.muted)
                .frame(width: 76, height: 50)
                .background(
                    chosen ? Palette.wash : hovering ? Palette.hover : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
            .accessibilityLabel(page.title)
            .accessibilityAddTraits(chosen ? .isSelected : [])
        }
    }
}

/// A titled group of rows, with an optional note under it.
struct SettingsSection<Rows: View>: View {
    let title: String?
    var note: String?
    @ViewBuilder let rows: () -> Rows

    init(_ title: String? = nil, note: String? = nil, @ViewBuilder rows: @escaping () -> Rows) {
        self.title = title
        self.note = note
        self.rows = rows
    }

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted).padding(.leading, 4)
            }
            VStack(spacing: 0, content: rows)
                .background(Palette.wash.opacity(0.55), in: shape)
                .overlay(shape.strokeBorder(Palette.hairline, lineWidth: 1))
            if let note {
                Text(note).font(.system(size: 11.5)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// A line between two rows, starting where their text does.
struct RowRule: View {
    var body: some View {
        Palette.hairline.frame(height: 1).padding(.leading, 47)
    }
}

/// A coloured symbol, as rows start with.
struct SymbolTile: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 6.5, style: .continuous))
    }
}

/// One setting: its symbol, what it is, what it does, and its control.
struct SettingRow<Control: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    var detail: String?
    @ViewBuilder let control: () -> Control

    init(_ title: String, _ detail: String? = nil, symbol: String, tint: Color, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.tint = tint
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            SymbolTile(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13)).foregroundStyle(Palette.ink)
                if let detail {
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

extension SettingRow where Control == Switch {
    /// A setting that's on or off.
    init(_ title: String, _ detail: String? = nil, symbol: String, tint: Color, on: Binding<Bool>) {
        self.init(title, detail, symbol: symbol, tint: tint) { Switch(on: on) }
    }
}

/// The colours rows use, so a page reads at a glance.
enum Tint {
    static let blue = Color(nsColor: .systemBlue)
    static let indigo = Color(nsColor: .systemIndigo)
    static let purple = Color(nsColor: .systemPurple)
    static let pink = Color(nsColor: .systemPink)
    static let red = Color(nsColor: .systemRed)
    static let orange = Color(nsColor: .systemOrange)
    static let yellow = Color(nsColor: .systemYellow)
    static let green = Color(nsColor: .systemGreen)
    static let teal = Color(nsColor: .systemTeal)
    static let gray = Color(nsColor: .systemGray)
}
