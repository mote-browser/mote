import SwiftUI

/// The text sizes Mote uses, by what the text is for.
enum TextStyle {
    /// A panel's name.
    case title
    /// A row's main text in a panel.
    case body
    /// A row in a menu or list.
    case row
    /// Counts and notes beside a list.
    case secondary
    /// A line under a row's title.
    case detail
    /// A heading over a group of rows.
    case caption
    /// Small print.
    case fine

    var font: Font {
        switch self {
        case .title: .system(size: 17, weight: .semibold)
        case .body: .system(size: 13)
        case .row: .system(size: 12.5)
        case .secondary: .system(size: 12)
        case .detail: .system(size: 11.5)
        case .caption: .system(size: 11.5, weight: .medium)
        case .fine: .system(size: 10.5)
        }
    }

    var color: Color {
        switch self {
        case .title, .body, .row: Palette.ink
        case .secondary, .detail, .caption, .fine: Palette.muted
        }
    }
}

extension View {
    /// Sets the font and colour for a kind of text.
    func textStyle(_ style: TextStyle) -> some View {
        font(style.font).foregroundStyle(style.color)
    }
}

/// Rounded rectangles Mote draws everything on, by size.
enum Rounded {
    /// Panels such as Settings and History.
    static let panel = RoundedRectangle(cornerRadius: 16, style: .continuous)
    /// Cards of rows inside a panel.
    static let card = RoundedRectangle(cornerRadius: 11, style: .continuous)
    /// Fields and wells.
    static let field = RoundedRectangle(cornerRadius: 10, style: .continuous)
    /// Rows and chips.
    static let row = RoundedRectangle(cornerRadius: 8, style: .continuous)
}

extension View {
    /// On a ground, clipped and outlined with a hairline.
    func surface(_ shape: RoundedRectangle, fill: Color = Palette.ground) -> some View {
        background(fill).clipShape(shape).overlay(shape.strokeBorder(Palette.hairline))
    }
}
