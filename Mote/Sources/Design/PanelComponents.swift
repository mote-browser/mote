import SwiftUI

// The pieces the Settings, History, Downloads, Passwords and Bookmarks panels
// are made of.

/// A panel: its name and a close button, what's in it, and an optional foot
/// under a hairline.
struct Plate<Content: View, Foot: View>: View {
    let title: String
    let width: CGFloat
    let close: () -> Void
    let content: Content
    let foot: Foot?

    init(
        _ title: String, width: CGFloat = 560, close: @escaping () -> Void, @ViewBuilder content: () -> Content,
        @ViewBuilder foot: () -> Foot
    ) {
        self.title = title
        self.width = width
        self.close = close
        self.content = content()
        self.foot = foot()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(title).textStyle(.title)
                Spacer(minLength: 0)
                Door(icon: "xmark", help: "Done   esc", act: close)
            }
            .padding(EdgeInsets(top: 18, leading: 22, bottom: 14, trailing: 22))

            content.padding(.horizontal, 22)

            if let foot {
                Palette.hairline.frame(height: 1).padding(.top, 18)
                foot.padding(.horizontal, 22).padding(.vertical, 14)
            } else {
                Spacer().frame(height: 20)
            }
        }
        .frame(width: width, alignment: .leading)
        .surface(Rounded.panel)
        .shadow(color: .black.opacity(0.16), radius: 34, y: 12)
    }
}

extension Plate where Foot == Never {
    /// A panel without a foot.
    init(_ title: String, width: CGFloat = 560, close: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.width = width
        self.close = close
        self.content = content()
        self.foot = nil
    }
}

/// Rows grouped in an outlined box.
struct Card<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0, content: content).surface(Rounded.card)
    }
}

/// The line between two rows of a card, starting where their text does.
struct Rule: View {
    var inset: CGFloat = 14

    var body: some View {
        Palette.hairline.frame(height: 1).padding(.leading, inset)
    }
}

/// A card row: a title, maybe a line under it, and a control at the end.
struct Line<Control: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let control: () -> Control

    init(_ title: String, _ detail: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).textStyle(.body)
                if let detail {
                    Text(detail).textStyle(.detail).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

/// A small heading over a card.
struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).textStyle(.caption).padding(.leading, 2)
    }
}

/// A field for narrowing a list, with a button to empty it.
struct SearchField: View {
    @Binding var text: String
    var prompt = "Search"
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Palette.muted.opacity(0.7)))
                .textFieldStyle(.plain)
                .textStyle(.body)
                .focused(focus)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Palette.faint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Palette.wash, in: Rounded.field)
    }
}

/// What an empty list says instead.
struct EmptyState: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(TextStyle.body.font)
            .foregroundStyle(Palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
    }
}

/// A small capsule button inside a row.
struct Quick: View {
    let title: String
    var tint: Color = Palette.ink
    let act: () -> Void

    init(_ title: String, tint: Color = Palette.ink, act: @escaping () -> Void) {
        self.title = title
        self.tint = tint
        self.act = act
    }

    var body: some View {
        Button(action: act) {
            Text(title)
                .font(TextStyle.detail.font)
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Palette.wash, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
