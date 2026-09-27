import AppKit
import MoteCore
import SwiftUI

/// The ⌘K palette over a page: the address field in tab-switcher mode, high
/// in the window over a dimmed page, with the open tabs listed below.
struct Omnibox: View {
    @ObservedObject var browser: Browser

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.16))
                .ignoresSafeArea()
                .onTapGesture { browser.dismiss() }
                .transition(.opacity)

            Composer(browser: browser, compact: true)
                .frame(width: Metrics.fieldWidth)
                .overlay(alignment: .top) {
                    if !browser.field.offers.isEmpty {
                        SuggestionList(browser: browser)
                            .offset(y: Composer.compactHeight + 8)
                            .transition(.opacity.combined(with: .offset(y: -4)))
                    }
                }
                .padding(.top, 120)
                .transition(.scale(scale: 0.97, anchor: .top).combined(with: .opacity))
                .animation(Motion.quick, value: browser.field.offers.isEmpty)
        }
    }
}

/// A blank tab: the bookmarks along the top (drawn by the card), and in the
/// middle the logo over a composer for an address or a search, laid out like
/// the prompt of a chat app.
struct NewTabPage: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 26) {
                MoteLogo()
                    .frame(width: 58, height: 57)
                Composer(browser: browser, compact: false)
                    .frame(width: min(Metrics.fieldWidth, max(280, geo.size.width - 64)))
                    // An overlay rather than a stack, so the list appearing or growing
                    // never moves the composer.
                    .overlay(alignment: .top) {
                        if !browser.field.offers.isEmpty {
                            SuggestionList(browser: browser)
                                .offset(y: Composer.fullHeight + 8)
                                .transition(.opacity.combined(with: .offset(y: -4)))
                        }
                    }
                    .animation(Motion.quick, value: browser.field.offers.isEmpty)
            }
            // Above centre: exact centre looks low under the toolbar.
            .position(x: geo.size.width / 2, y: geo.size.height * 0.42)
        }
        .background(Palette.ground)
        .contentShape(Rectangle())
        // A click on the empty page puts the caret back in the composer.
        .onTapGesture { browser.field.askFocus() }
    }
}

/// The address field dressed as a chat prompt: the text on top, and a row
/// beneath for where the words go and the button that sends them.
struct Composer: View {
    @ObservedObject var browser: Browser
    /// A single row, for the palette.
    let compact: Bool

    static let compactHeight: CGFloat = 52
    static let fullHeight: CGFloat = 104

    @State private var shake: CGFloat = 0
    @State private var refused = false

    private var hasText: Bool { !browser.field.typed.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: browser.field.switching ? "square.on.square" : "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 16)
                AddressField(
                    browser: browser, size: 15,
                    placeholder: browser.field.switching ? "Switch to a tab" : "Search or enter address"
                )
                .frame(height: 22)
            }
            .padding(.horizontal, 16)
            .frame(height: Composer.compactHeight)

            if !compact {
                HStack(spacing: 8) {
                    Chip(browser: browser)
                    Spacer(minLength: 0)
                    Send(ready: hasText) { browser.submit() }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .frame(height: Composer.fullHeight - Composer.compactHeight, alignment: .bottom)
            }
        }
        .frame(height: compact ? Composer.compactHeight : Composer.fullHeight)
        .background {
            ZStack {
                if !compact { Breath() }
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Palette.ground)
                    .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
                    .shadow(color: .black.opacity(0.07), radius: 24, y: 10)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(refused ? Color.red.opacity(0.35) : Palette.hairline, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture { browser.field.askFocus() }
        .modifier(Shake(travel: shake))
        .onChange(of: browser.field.refusals) { _, _ in
            shake = 0
            refused = true
            withAnimation(.easeOut(duration: 0.5)) { shake = 1 }
        }
        .onChange(of: browser.field.typed) { _, _ in
            guard refused else { return }
            withAnimation(Motion.quick) { refused = false }
        }
        .animation(Motion.settle, value: refused)
    }

    /// Where the words go: the search engine, which Settings changes.
    private struct Chip: View {
        @ObservedObject var browser: Browser
        @State private var hovering = false

        var body: some View {
            Button {
                browser.tuning = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 11, weight: .medium))
                    Text(browser.prefs.engine.name(custom: browser.prefs.customEngine))
                        .font(.system(size: 12))
                }
                .foregroundStyle(hovering ? Palette.ink.opacity(0.8) : Palette.muted)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Palette.veil.opacity(hovering ? 1.4 : 0.7))
                        .strokeBorder(Palette.edge, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(Pressed())
            .onHover { hovering = $0 }
            .help("Searches go to this engine — change it in Settings")
            .animation(Motion.hover, value: hovering)
        }
    }

    /// The round send button, filled once there is something to send.
    private struct Send: View {
        let ready: Bool
        let act: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: act) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ready ? Palette.ground : Palette.muted)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(ready ? Palette.ink.opacity(hovering ? 0.8 : 1) : Palette.veil))
                    .contentShape(Circle())
            }
            .buttonStyle(Pressed())
            .disabled(!ready)
            .onHover { hovering = $0 }
            .help("Go   ↩")
            .accessibilityLabel("Go")
            .animation(Motion.quick, value: ready)
            .animation(Motion.hover, value: hovering)
        }
    }
}

/// Suggestions for what has been typed: history, a search, or open tabs.
struct SuggestionList: View {
    @ObservedObject var browser: Browser

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(browser.field.offers.enumerated()), id: \.element.id) { index, offer in
                Row(offer: offer, picked: browser.field.picked == index)
                    .contentShape(Rectangle())
                    .onTapGesture { browser.take(offer) }
            }
        }
        .padding(6)
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 24, y: 10)
    }

    private struct Row: View {
        let offer: Suggestion
        /// Keyboard selection. Hover gets a lighter highlight and does not
        /// change the selection.
        let picked: Bool

        @State private var hovering = false

        var body: some View {
            HStack(spacing: 10) {
                Group {
                    switch offer.kind {
                    case .search:
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.muted)
                    case .open:
                        // Already open in a tab; choosing it switches to that tab.
                        Image(systemName: "square.on.square")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Palette.muted)
                    default:
                        Mark(
                            icon: offer.url.host().flatMap { Favicons.shared.cached($0.lowercased()) },
                            letter: String((offer.url.host() ?? "•").replacingOccurrences(of: "www.", with: "").prefix(1)).uppercased(),
                            size: 15)
                    }
                }
                .frame(width: 16)
                Text(offer.key)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)

                if !offer.title.isEmpty {
                    Text(offer.title)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
                if picked {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.faint)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(picked ? Palette.wash : hovering ? Palette.hover : .clear)
            }
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
            .animation(Motion.hover, value: picked)
        }
    }
}

/// The pebble from the app icon, drawn from its SVG: the same path, filled
/// with the same four soft lights.
struct MoteLogo: View {
    var body: some View {
        ZStack {
            Logomark().fill(MoteLogo.base)
            ForEach(Array(MoteLogo.lights.enumerated()), id: \.offset) { _, light in
                GeometryReader { geo in
                    Logomark().fill(
                        RadialGradient(
                            stops: [
                                .init(color: light.colour, location: 0),
                                .init(color: light.colour.opacity(0.75), location: 0.45),
                                .init(color: light.colour.opacity(0), location: 1),
                            ],
                            center: light.centre, startRadius: 0, endRadius: light.radius * geo.size.width))
                }
            }
        }
        .aspectRatio(Logomark.canvas, contentMode: .fit)
        .shadow(color: Color(red: 0.55, green: 0.33, blue: 0.22).opacity(0.18), radius: 10, y: 5)
        .accessibilityHidden(true)
    }

    private static let base = Color(red: 0xF2 / 255, green: 0xD9 / 255, blue: 0xC4 / 255)

    /// The gradients of pebble.svg, moved into the pebble's own box (see
    /// `Logomark.canvas`): centres as fractions of it, radii as fractions of its width.
    private static let lights: [(colour: Color, centre: UnitPoint, radius: CGFloat)] = [
        (Color(red: 1, green: 0xF3 / 255, blue: 0xE6 / 255), UnitPoint(x: 124 / 564, y: 100 / 550), 330 / 564),
        (Color(red: 0xF6 / 255, green: 0xC6 / 255, blue: 0xA8 / 255), UnitPoint(x: 474 / 564, y: 160 / 550), 310 / 564),
        (Color(red: 0xE7 / 255, green: 0xA5 / 255, blue: 0x8E / 255), UnitPoint(x: 384 / 564, y: 490 / 550), 330 / 564),
        (Color(red: 0xF4 / 255, green: 0xDC / 255, blue: 0xC0 / 255), UnitPoint(x: 84 / 564, y: 450 / 550), 290 / 564),
    ]
}

/// Pulsing glow under the address field, implemented as a layer shadow
/// animated by Core Animation. The animation runs in the render server; a
/// SwiftUI animation would redraw on the main thread every frame.
private struct Breath: NSViewRepresentable {
    /// Shadow opacity. A shadow renders at about 0.7x the darkness of an
    /// equally opaque blurred fill, so 7% matches a 5% fill with a 26 pt blur.
    static let strength: Swift.Float = 0.07

    func makeNSView(context: Context) -> NSView { Lung() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Lung: NSView {
        private let glow = CALayer()
        private var breathed: CGSize = .zero

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            glow.shadowOpacity = Breath.strength
            glow.shadowOffset = .zero
            glow.shadowRadius = 26
            layer?.addSublayer(glow)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        /// Re-resolves the ink color for the current appearance.
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            effectiveAppearance.performAsCurrentDrawingAppearance { glow.shadowColor = Palette.NS.ink.cgColor }
        }

        override func layout() {
            super.layout()
            guard bounds.size != breathed, bounds.width > 0 else { return }
            breathed = bounds.size
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            glow.bounds = bounds
            glow.position = CGPoint(x: bounds.midX, y: bounds.midY)
            glow.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 26, cornerHeight: 26, transform: nil)
            effectiveAppearance.performAsCurrentDrawingAppearance { glow.shadowColor = Palette.NS.ink.cgColor }
            CATransaction.commit()
            // Scale 0.97–1.03 and opacity 0.65–1.0, 2.6 s each way, repeating.
            let size = CABasicAnimation(keyPath: "transform.scale")
            size.fromValue = 0.97
            size.toValue = 1.03
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.65
            fade.toValue = 1.0
            let both = CAAnimationGroup()
            both.animations = [size, fade]
            both.duration = 2.6
            both.autoreverses = true
            both.repeatCount = .infinity
            both.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            glow.add(both, forKey: "breath")
        }
    }
}
