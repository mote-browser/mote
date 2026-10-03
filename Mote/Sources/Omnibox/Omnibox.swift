import AppKit
import MoteAI
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
    /// Times the logo has let a drop of light fall onto the composer.
    @State private var drops = 0

    private static let logo = CGSize(width: 72, height: 70)
    private static let gap: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: Self.gap) {
                MoteLogo(alive: browser.field.asksAssistant)
                    .padding(-MoteLogo.spill)
                    .frame(width: Self.logo.width, height: Self.logo.height)
                    .overlay {
                        Logomark().stroke(Palette.hairline, lineWidth: 1)
                            .opacity(browser.field.asksAssistant ? 0 : 1)
                            .animation(.easeOut(duration: 0.15), value: browser.field.asksAssistant)
                            .allowsHitTesting(false)
                    }
                    .background {
                        Breath(pulsing: false, warm: browser.field.asksAssistant)
                            .opacity(browser.field.asksAssistant ? 1 : 0)
                            .animation(.easeInOut(duration: 0.3), value: browser.field.asksAssistant)
                    }
                Composer(browser: browser, compact: false)
                    .frame(width: min(650, max(280, geo.size.width - 64)))
                    // An overlay rather than a stack, so the list appearing or growing
                    // never moves the composer.
                    .overlay(alignment: .top) {
                        if browser.assistantLeads && MentionMenu.query(in: browser.field.typed) != nil {
                            EmptyView()
                        } else if !browser.field.offers.isEmpty {
                            SuggestionList(browser: browser)
                                .offset(y: Composer.height(for: browser) + 8)
                                .transition(.opacity.combined(with: .offset(y: -4)))
                        }
                    }
                    .animation(Motion.quick, value: browser.field.offers.isEmpty)
                    .animation(Motion.quick, value: browser.field.typed.isEmpty)
            }
            // Asking begins: a drop of light falls from the logo onto the composer's border.
            .overlay(alignment: .top) {
                LightDrop(trigger: drops, from: Self.logo.height, to: Self.logo.height + Self.gap)
            }
            .onChange(of: browser.field.asksAssistant) { _, asking in
                if asking, !Glow.stillness { drops += 1 }
            }
            // Above centre: exact centre looks low under the toolbar.
            .position(x: geo.size.width / 2, y: geo.size.height * 0.46)
        }
        .background { DragStrip(click: { browser.field.askFocus() }) }
    }
}

/// A drop of light the logo lets fall onto the composer as asking begins:
/// the last of the halo that closed round the logo, it falls from under it
/// faster and faster, stretching, and splashes where it lands, as the
/// composer's halo starts from that point.
/// `from` and `to` are heights from the top of the logo.
private struct LightDrop: View {
    let trigger: Int
    let from: CGFloat
    let to: CGFloat

    private struct Fall {
        var y: CGFloat = 0
        var opacity: Double = 0
        var size: CGFloat = 0.3
        var stretch: CGFloat = 1
    }

    nonisolated private static let side: CGFloat = 10

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color(nsColor: Glow.cream), Color(nsColor: Glow.peach), Color(nsColor: Glow.clay).opacity(0.6)],
                    center: .center,
                    startRadius: 0, endRadius: Self.side / 2)
            )
            .frame(width: Self.side, height: Self.side)
            .shadow(color: Color(nsColor: Glow.clay).opacity(0.9), radius: 6)
            .keyframeAnimator(initialValue: Fall(), trigger: trigger) { drop, fall in
                drop.scaleEffect(x: fall.size / fall.stretch.squareRoot(), y: fall.size * fall.stretch)
                    .opacity(fall.opacity)
                    .offset(y: fall.y - Self.side / 2)
            } keyframes: { _ in
                // It leaves at maximum compression and lands at `Glow.impact`.
                KeyframeTrack(\.y) {
                    LinearKeyframe(from, duration: Glow.release)
                    LinearKeyframe(to, duration: Glow.fall, timingCurve: .easeIn)
                    LinearKeyframe(to, duration: 0.2)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: Glow.release - 0.03)
                    LinearKeyframe(1, duration: 0.03)
                    LinearKeyframe(1, duration: Glow.fall)
                    LinearKeyframe(0, duration: 0.2, timingCurve: .easeOut)
                }
                KeyframeTrack(\.size) {
                    LinearKeyframe(0.4, duration: Glow.release)
                    LinearKeyframe(1, duration: 0.15, timingCurve: .easeOut)
                    LinearKeyframe(0.8, duration: 0.15)
                    LinearKeyframe(2.2, duration: 0.2, timingCurve: .easeOut)
                }
                KeyframeTrack(\.stretch) {
                    LinearKeyframe(1, duration: Glow.release)
                    LinearKeyframe(1.8, duration: Glow.fall, timingCurve: .easeIn)
                    LinearKeyframe(0.35, duration: 0.2, timingCurve: .easeOut)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The address field dressed as a chat prompt: the text on top, and a row
/// beneath for where the words go and the button that sends them.
struct Composer: View {
    @ObservedObject var browser: Browser
    /// A single row, for the palette.
    let compact: Bool

    static let compactHeight: CGFloat = 52
    static let fullHeight: CGFloat = 112
    private var inputHeight: CGFloat { compact ? Self.compactHeight : 58 }

    @State private var shake: CGFloat = 0
    @State private var refused = false
    @State private var mentionSelection = ComposerSelection()
    @State private var dismissedMentionDraft: String?
    @State private var escapePick: Int?

    private var hasText: Bool { !browser.field.typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var engine: String { browser.prefs.engine.name(custom: browser.prefs.customEngine) }
    private var assistant: Assistant { .shared }
    /// Return asks here: one of the assistant's modes is chosen.
    private var leads: Bool { !compact && browser.field.asksAssistant }
    private var mentionQuery: String? { leads ? MentionMenu.query(in: browser.field.typed) : nil }
    private var mentionables: [MentionMenu.Candidate] {
        guard browser.field.stagedMentionIDs.count < Conversation.mentionLimit else { return [] }
        let mentioned = Set(stagedTabs.map(\.url))
        return browser.mentionCandidates(excluding: browser.active, mentioned: mentioned).filter { candidate in
            guard let id = UUID(uuidString: candidate.id) else { return false }
            return browser.tab(id).map { PageSharing.canShare($0.address) } ?? false
        }
    }
    private var mentionMatches: [MentionMenu.Candidate] {
        guard let mentionQuery else { return [] }
        return MentionMenu.matching(mentionQuery, in: mentionables)
    }
    private var mentionItems: [ComposerPickerItem] { mentionMatches.map(ComposerPickerItem.mention) }
    private var mentionPickerVisible: Bool { mentionQuery != nil && !mentionItems.isEmpty && dismissedMentionDraft != browser.field.typed }
    private var stagedTabs: [AddressEntry.StagedMention] { browser.field.stagedMentions }
    private var showStagedContexts: Bool {
        leads && (!stagedTabs.isEmpty || browser.field.capturingMentionContext)
    }

    static let contextHeight: CGFloat = 40

    static func height(for browser: Browser) -> CGFloat {
        let showContexts =
            browser.field.asksAssistant
            && (!browser.field.stagedMentions.isEmpty || browser.field.capturingMentionContext)
        return fullHeight + (showContexts ? contextHeight : 0)
    }

    private var contentHeight: CGFloat { compact ? Self.compactHeight : Self.height(for: browser) }
    /// The field's symbol: what Return will do now, with ⌘ held or not.
    private var symbol: String {
        if browser.field.switching { return "square.on.square" }
        return leads ? "sparkle" : "magnifyingglass"
    }

    private var placeholder: String {
        if browser.field.switching { return "Switch to a tab" }
        if compact || !leads { return "Search or enter an address" }
        return assistant.mode == .research ? "What should be researched?" : "Ask anything"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .contentTransition(.symbolEffect(.replace))
                    .font(.system(size: compact ? 13 : 14, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 16)
                AddressField(
                    browser: browser, size: compact ? 15 : 16,
                    placeholder: placeholder,
                    moveSelection: moveMentionSelection,
                    choose: confirmMention,
                    escape: dismissMentionPicker
                )
                .frame(height: compact ? 22 : 28)
            }
            .padding(.horizontal, compact ? 16 : 20)
            .frame(height: inputHeight)

            if !compact {
                if showStagedContexts { stagedContexts.frame(height: Self.contextHeight) }
                HStack(spacing: 10) {
                    AskToggle(asks: leads, engine: engine) { asks in
                        browser.field.asksAssistant = asks
                        if asks { assistant.prepare() }
                        browser.field.askFocus()
                    }
                    if leads {
                        Rectangle().fill(Palette.edge).frame(width: 1, height: 14).transition(.opacity)
                        ToolToggles().transition(.opacity)
                    }
                    Spacer(minLength: 0)
                    if leads {
                        AIChip(browser: browser).transition(.opacity)
                    }
                    RoundButton(
                        symbol: "arrow.up", filled: hasText && !browser.field.capturingMentionContext,
                        help: leads ? "Ask   ↩" : "Search or go   ↩"
                    ) {
                        guard !browser.field.capturingMentionContext else { return }
                        leads ? browser.ask() : browser.submit(searching: true)
                    }
                }
                .animation(Motion.quick, value: hasText)
                .animation(Motion.settle, value: leads)
                .padding(.leading, 12)
                .padding(.trailing, 11)
                .padding(.bottom, 10)
                .frame(height: contentHeight - inputHeight - (showStagedContexts ? Self.contextHeight : 0), alignment: .bottom)
            }
        }
        .frame(height: contentHeight)
        .background {
            ZStack {
                if !compact {
                    AskAura(on: leads).padding(-AskAura.spill)
                }
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(compact ? Palette.ground : Palette.composer)
                    .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
                    .shadow(color: .black.opacity(0.07), radius: 24, y: 10)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(refused ? Color.red.opacity(0.35) : Palette.hairline.opacity(leads ? 0 : 1), lineWidth: 1)
                .allowsHitTesting(false)
                // Asking, the plain border gives way as the halo drawn from the logo's drop goes round.
                .animation(leads ? .easeInOut(duration: 0.5).delay(Glow.impact + 0.5) : Motion.settle, value: leads)
        }
        .overlay {
            // Asking: the logo's colours run round the border.
            if !compact { AskHalo(on: leads).padding(-AskHalo.spill) }
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
        .overlay(alignment: .top) {
            if mentionPickerVisible {
                ComposerPicker(items: mentionItems, highlighted: mentionSelection.highlightedIndex, choose: chooseMention)
                    .offset(y: contentHeight + 8)
                    .zIndex(2)
            }
        }
        .onChange(of: browser.field.typed) { _, _ in
            mentionSelection.reset()
            dismissedMentionDraft = nil
        }
        .onChange(of: mentionItems) { _, _ in mentionSelection.reset() }
        .onChange(of: mentionPickerVisible) { _, visible in
            if visible { holdEscapePick() } else { releaseEscapePick() }
        }
        .onChange(of: browser.field.picked) { oldValue, newValue in
            guard oldValue == escapePick, newValue == nil, mentionPickerVisible else { return }
            escapePick = nil
            dismissedMentionDraft = browser.field.typed
            mentionSelection.reset()
        }
        .onDisappear { releaseEscapePick() }
        .animation(Motion.settle, value: refused)
        .animation(Motion.settle, value: leads)
        .animation(Motion.quick, value: mentionItems)
        .animation(Motion.quick, value: showStagedContexts)
    }

    private var stagedContexts: some View {
        HStack(spacing: 6) {
            if !stagedTabs.isEmpty {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 6) {
                        ForEach(stagedTabs) { staged in
                            ContextChip(title: staged.title.isEmpty ? (staged.url.host() ?? staged.url.absoluteString) : staged.title) {
                                browser.field.unstageMention(staged.id)
                            }
                            .overlay(alignment: .topTrailing) {
                                if browser.tab(staged.id)?.address != staged.url {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(Palette.muted)
                                        .offset(x: -4, y: 3)
                                        .help("This tab changed pages. Remove it and mention the current page again.")
                                }
                            }
                        }
                    }
                }
                .frame(height: 28)
                .accessibilityLabel("Mentioned pages")
            }
            Spacer(minLength: 0)
            if browser.field.capturingMentionContext {
                ProgressView().controlSize(.small)
                Text("Reading")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.muted)
                    .accessibilityLabel("Reading selected pages")
            } else if browser.field.stagedMentions.count >= Conversation.mentionLimit {
                Text("5 / 5")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .help("Up to five pages can be shared")
                    .accessibilityLabel("Maximum five pages shared")
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
    }

    private func chooseMention(_ item: ComposerPickerItem) {
        guard case .mention(let candidate) = item, let id = UUID(uuidString: candidate.id),
            let tab = browser.tab(id), let url = tab.address,
            browser.field.stageMention(id, url: url, title: candidate.title)
        else { return }
        browser.field.typed = MentionMenu.cleared(browser.field.typed)
        mentionSelection.reset()
        dismissedMentionDraft = nil
    }

    private func confirmMention() -> Bool {
        guard mentionPickerVisible,
            let index = mentionSelection.confirmedIndex(count: mentionItems.count), mentionItems.indices.contains(index)
        else { return false }
        chooseMention(mentionItems[index])
        return true
    }

    private func moveMentionSelection(_ step: Int) -> Bool {
        guard mentionPickerVisible else { return false }
        mentionSelection.move(step, count: mentionItems.count)
        return true
    }

    private func dismissMentionPicker() -> Bool {
        guard mentionPickerVisible else { return false }
        dismissedMentionDraft = browser.field.typed
        mentionSelection.reset()
        releaseEscapePick()
        return true
    }

    private func holdEscapePick() {
        guard mentionPickerVisible, escapePick == nil, browser.field.picked == nil else { return }
        escapePick = -1
        browser.field.picked = -1
    }

    private func releaseEscapePick() {
        guard escapePick != nil else { return }
        escapePick = nil
        if browser.field.picked == -1 { browser.field.picked = nil }
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

/// Pulsing glow under the address field, implemented as a layer shadow
/// animated by Core Animation. The animation runs in the render server; a
/// SwiftUI animation would redraw on the main thread every frame.
private struct Breath: NSViewRepresentable {
    var pulsing = true
    var warm = false
    /// Shadow opacity. A shadow renders at about 0.7x the darkness of an
    /// equally opaque blurred fill, so 7% matches a 5% fill with a 26 pt blur.
    static let strength: Swift.Float = 0.07

    func makeNSView(context: Context) -> NSView { Lung(pulsing: pulsing) }
    func updateNSView(_ view: NSView, context: Context) { (view as? Lung)?.setWarm(warm) }

    private final class Lung: NSView {
        private let glow = CALayer()
        private let pulsing: Bool
        private var warm = false
        private var breathed: CGSize = .zero

        init(pulsing: Bool) {
            self.pulsing = pulsing
            super.init(frame: .zero)
            wantsLayer = true
            glow.shadowOpacity = pulsing ? Breath.strength : 0.02
            glow.shadowOffset = .zero
            glow.shadowRadius = pulsing ? 26 : 12
            layer?.addSublayer(glow)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func setWarm(_ warm: Bool) {
            guard warm != self.warm else { return }
            self.warm = warm
            let from = glow.presentation()?.shadowColor ?? glow.shadowColor
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            tint()
            if !Glow.stillness {
                let colour = CABasicAnimation(keyPath: "shadowColor")
                colour.fromValue = from
                colour.toValue = glow.shadowColor
                colour.duration = 0.8
                colour.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0, 0.2, 1)
                glow.add(colour, forKey: "colour")
            }
            CATransaction.commit()
        }

        private func tint() {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                glow.shadowColor = warm ? Glow.clay.cgColor : Palette.NS.ink.cgColor
            }
        }

        /// Re-resolves the ink color for the current appearance.
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            tint()
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
            tint()
            CATransaction.commit()
            guard pulsing, !Glow.stillness else { return }
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
