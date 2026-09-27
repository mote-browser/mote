import SwiftUI

/// First-run setup, after the arrival (see Arrival.swift): a single card over
/// the new tab that changes shape as it goes. It asks only what the browser
/// can't guess — what to bring from another browser, where the tabs go, and
/// whether to be the default — and drops any question that is already settled.
struct WelcomePanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences

    private enum Step { case bring, hold, links }

    @State private var steps: [Step] = []
    @State private var index = 0
    @State private var shown = false
    @State private var leaving = false

    // Import state. `source` stays nil until picked (nil means the first
    // installed browser) so the filesystem scan runs once.
    @State private var sources: [ChromiumImporter.Source] = []
    @State private var source: ChromiumImporter.Source?
    @State private var wantsPasswords = true
    @State private var wantsHistory = true
    @State private var wantsBookmarks = true
    @State private var bringing = false
    @State private var brought: Brought?

    @State private var isDefault = AppDelegate.isDefault
    @State private var asked = false

    private var step: Step? { steps.indices.contains(index) ? steps[index] : nil }

    var body: some View {
        ZStack {
            Color.black.opacity(shown && !leaving ? 0.16 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(!leaving)

            if shown, !leaving, let step {
                card(step)
                    .transition(
                        .asymmetric(
                            insertion: .offset(y: 28).combined(with: .scale(scale: 0.94)).combined(with: .opacity),
                            removal: .scale(scale: 0.96).combined(with: .opacity)))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: shown)
        .animation(.easeIn(duration: 0.25), value: leaving)
        .task { await begin() }
    }

    // MARK: - The card

    private func card(_ step: Step) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            if steps.count > 1 { dots }
            Group {
                switch step {
                case .bring: bring
                case .hold: hold
                case .links: links
                }
            }
            .id(step)
            .transition(.blurReplace)
        }
        .padding(28)
        .frame(width: 440, alignment: .leading)
        .welcomeGlass()
        .shadow(color: .black.opacity(0.12), radius: 30, y: 12)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: step)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: brought)
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(steps.indices, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Palette.ink : Palette.faint)
                    .frame(width: i == index ? 16 : 5, height: 5)
            }
        }
        .animation(Motion.glide, value: index)
    }

    private var bring: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading("Bring your things over", "Nothing in \(chosen?.name ?? "the other browser") changes.")

            if sources.count > 1 {
                Segmented(
                    options: sources.map { ($0, $0.name) },
                    selection: Binding(get: { chosen ?? sources[0] }, set: { source = $0 }))
            }

            if let brought {
                HStack(spacing: 18) {
                    if let n = brought.bookmarks { Tally(value: n, label: "bookmarks") }
                    if let n = brought.places { Tally(value: n, label: "places") }
                    if let n = brought.passwords { Tally(value: n, label: "passwords") }
                }
                if let trouble = brought.trouble {
                    Text(trouble).font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Choice("Bookmarks", on: $wantsBookmarks)
                    Choice("History", on: $wantsHistory)
                    Choice("Passwords", "macOS asks once for its keychain key", on: $wantsPasswords)
                }
            }

            HStack(spacing: 10) {
                if brought == nil {
                    Big(bringing ? "Bringing…" : "Bring them over", filled: true) { bringAll() }
                        .disabled(bringing || !(wantsPasswords || wantsHistory || wantsBookmarks))
                    if bringing { Ring(size: 10) }
                    Spacer()
                    if !bringing { Quiet("Not now") { next() } }
                } else {
                    Big("Continue", filled: true) { next() }
                }
            }
        }
    }

    private var hold: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading("Tabs on top, or down the side", "The window changes as you pick. ⇧⌘S switches any time.")
            TabLayoutChoice(prefs: prefs)
            HStack {
                Spacer()
                Big("Continue", filled: true) { next() }
            }
        }
    }

    private var links: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading(
                "Open links here",
                "A click in Mail, Slack or a PDF goes to your default browser. It can be this one.")
            HStack(spacing: 10) {
                if isDefault {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolEffect(.bounce, value: isDefault)
                        Text("Mote is your default browser")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .transition(.blurReplace)
                } else {
                    Big("Make Mote the default", filled: true) {
                        asked = true
                        AppDelegate.becomeDefault { _ in
                            isDefault = AppDelegate.isDefault
                            if isDefault { later(1.1) { next() } }
                        }
                    }
                    Spacer()
                    Quiet(asked ? "Keep as is" : "Not now") { next() }
                }
            }
            .animation(Motion.settle, value: isDefault)
        }
    }

    // MARK: - Flow

    private func begin() async {
        sources = ChromiumImporter.installed()
        steps = [sources.isEmpty ? nil : .bring, .hold, isDefault ? nil : .links].compactMap { $0 }
        // Let the window settle in after the arrival before the card rises.
        try? await Task.sleep(for: .seconds(0.35))
        shown = true
    }

    private func next() {
        guard index + 1 < steps.count else { return finish() }
        index += 1
    }

    /// The card dissolves and the address field takes focus.
    private func finish() {
        leaving = true
        later(0.25) { browser.finishWelcome() }
    }

    private func later(_ seconds: Double, _ act: @escaping () -> Void) {
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            act()
        }
    }

    // MARK: - Import

    private var chosen: ChromiumImporter.Source? { source ?? sources.first }

    private struct Brought: Equatable {
        var bookmarks: Int?
        var places: Int?
        var passwords: Int?
        var trouble: String?
    }

    private func bringAll() {
        guard let source = chosen else { return }
        bringing = true
        Task {
            var result = Brought()
            if wantsBookmarks { result.bookmarks = browser.takeBookmarks(from: source) }
            if wantsHistory { result.places = await browser.takePlaces(from: source) }
            if wantsPasswords {
                switch await browser.logins.bring(from: source) {
                case .success(let n): result.passwords = n
                case .failure(.locked): result.trouble = "Passwords: macOS didn't hand over the key. Settings › Passwords can try again."
                case .failure(.unreadable): result.trouble = "Passwords: nothing readable."
                }
            }
            bringing = false
            brought = result
        }
    }

    private func heading(_ title: String, _ line: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Text(line)
                .font(.system(size: 13.5))
                .foregroundStyle(Palette.muted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Components

    private struct Big: View {
        let title: String
        var filled = false
        let act: () -> Void
        @State private var hovering = false

        init(_ title: String, filled: Bool = false, act: @escaping () -> Void) {
            self.title = title
            self.filled = filled
            self.act = act
        }

        var body: some View {
            Button(action: act) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(filled ? Palette.ground : Palette.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(filled ? Palette.ink : (hovering ? Palette.hover : Palette.wash), in: Capsule())
                    .scaleEffect(hovering ? 1.03 : 1)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Motion.press, value: hovering)
        }
    }

    /// The secondary way on: plain text.
    private struct Quiet: View {
        let title: String
        let act: () -> Void
        init(_ title: String, act: @escaping () -> Void) {
            self.title = title
            self.act = act
        }
        var body: some View {
            Button(title, action: act)
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
        }
    }

    private struct Choice: View {
        let title: String
        let detail: String?
        @Binding var on: Bool

        init(_ title: String, _ detail: String? = nil, on: Binding<Bool>) {
            self.title = title
            self.detail = detail
            _on = on
        }

        var body: some View {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13.5)).foregroundStyle(Palette.ink)
                    if let detail {
                        Text(detail).font(.system(size: 11.5)).foregroundStyle(Palette.muted)
                    }
                }
                Spacer()
                Switch(on: $on)
            }
        }
    }

    /// A number that counts up to `value` when it appears.
    private struct Tally: View {
        let value: Int
        let label: String
        @State private var shown = 0.0

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Count(value: shown)
                    .font(.system(size: 26, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.ink)
                Text(label).font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            .onAppear { withAnimation(.easeOut(duration: 1.2)) { shown = Double(value) } }
        }

        private struct Count: View, Animatable {
            var value: Double
            var animatableData: Double {
                get { value }
                set { value = newValue }
            }
            var body: some View { Text(Int(value.rounded()), format: .number) }
        }
    }
}

extension View {
    /// Liquid Glass where the system has it, a material elsewhere.
    @ViewBuilder
    fileprivate func welcomeGlass() -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: .rect(cornerRadius: 26))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }
}
