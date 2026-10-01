import SwiftUI

/// A bounded chip for one shared tab, with a remove target that never shrinks.
struct ContextChip: View {
    let title: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "at")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Palette.muted)
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink.opacity(0.8))
                .lineLimit(1)
                .frame(maxWidth: 160, alignment: .leading)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Stop mentioning this tab")
            .accessibilityLabel("Stop mentioning \(title)")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: 26)
        .background(Palette.wash, in: Rounded.row)
        .overlay(Rounded.row.strokeBorder(Palette.hairline))
        .accessibilityElement(children: .contain)
    }
}
