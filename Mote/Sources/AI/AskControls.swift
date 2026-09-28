import MoteAI
import MoteCore
import SwiftUI

// How the composers say what Return does and who answers. The new tab's
// first says whether Return searches or asks; where it asks, as in a chat,
// the assistant's tools (the web, research) sit on the left and the model,
// a quiet chip, on the right by the send button.

/// Who answers and how, in a few words: "Sonnet · Web".
@MainActor
enum AskLabel {
    static func model(_ assistant: Assistant) -> String {
        let provider = assistant.provider
        guard !assistant.model(for: provider).isEmpty else { return provider.name }
        // "opencode/big-pickle": the part before the slash is where it comes from.
        return String(assistant.modelName(for: provider).split(separator: "/").last ?? "")
    }

    static func full(_ assistant: Assistant) -> String {
        let mode = assistant.mode
        return mode == .chat ? model(assistant) : "\(model(assistant)) · \(mode.title)"
    }
}

/// The assistant, as quiet text in a composer: the model and the mode,
/// opening the choices for both. `lit` while ⌘ is held over the new tab's.
struct AIChip: View {
    let browser: Browser
    var lit = false
    @State private var open = false
    @State private var hovering = false
    private var assistant: Assistant { .shared }

    var body: some View {
        Button {
            open.toggle()
        } label: {
            AskChipLabel(assistant: assistant, chevron: true)
                .foregroundStyle(lit || hovering || open ? Palette.ink.opacity(0.85) : Palette.muted)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(Palette.veil.opacity(hovering || open ? 1 : 0), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(Pressed())
        .fixedSize()
        .onHover { inside in
            hovering = inside
            if inside { assistant.prepare() }
        }
        .popover(isPresented: $open, arrowEdge: .bottom) { AskMenu(browser: browser) { open = false } }
        .help("The model that answers")
        .accessibilityLabel("Model: \(AskLabel.model(assistant))")
        .animation(Motion.hover, value: hovering)
        .animation(Motion.quick, value: lit)
    }
}

/// The model, as the chip names it.
struct AskChipLabel: View {
    let assistant: Assistant
    var chevron = false

    var body: some View {
        HStack(spacing: 5) {
            Text(AskLabel.model(assistant)).font(.system(size: 12)).lineLimit(1)
            if chevron {
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.6)
            }
        }
    }
}

/// The choices behind the model chip: the model, and the provider.
struct AskMenu: View {
    let browser: Browser
    let close: () -> Void
    private var assistant: Assistant { .shared }

    var body: some View {
        let provider = assistant.provider
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Model").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
                    Spacer()
                    ProviderMenu()
                }
                .padding(.horizontal, 4)
                ModelList(provider: provider, close: close)
            }
            Rule()
            Button {
                close()
                browser.openSettings(at: .ai)
            } label: {
                HStack {
                    Text("AI Settings…").font(.system(size: 12.5))
                    Spacer()
                }
                .foregroundStyle(Palette.ink.opacity(0.8))
                .padding(.horizontal, 8)
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 292)
        .onAppear { assistant.prepare() }
    }

    /// The provider, with a menu to change it.
    private struct ProviderMenu: View {
        private var assistant: Assistant { .shared }

        var body: some View {
            Menu {
                providers("On This Mac", Provider.all.filter { $0.kind != .cloud })
                providers("With an API Key", Provider.all.filter { $0.kind == .cloud })
            } label: {
                HStack(spacing: 4) {
                    Text(assistant.provider.name).font(.system(size: 11.5))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(Palette.muted)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Who answers")
        }

        @ViewBuilder
        private func providers(_ title: String, _ list: [Provider]) -> some View {
            Section(title) {
                ForEach(list) { provider in
                    let status = assistant.status(of: provider)
                    let usable = status == .ready || provider.id == assistant.providerID
                    Button {
                        assistant.providerID = provider.id
                    } label: {
                        let name = usable ? provider.name : "\(provider.name) — \(AskMenu.words(for: status))"
                        if provider.id == assistant.providerID { Label(name, systemImage: "checkmark") } else { Text(name) }
                    }
                    .disabled(!usable)
                }
            }
        }
    }

    /// The provider's models, the chosen one ticked.
    private struct ModelList: View {
        let provider: Provider
        let close: () -> Void
        private var assistant: Assistant { .shared }

        var body: some View {
            let chosen = assistant.model(for: provider)
            let listed = Array((assistant.models[provider.id] ?? provider.suggested).prefix(40))
            ScrollView {
                VStack(spacing: 1) {
                    if provider.kind == .agent {
                        row("Default model", on: chosen.isEmpty) { assistant.change(provider) { $0.model = "" } }
                    }
                    ForEach(listed) { model in
                        row(model.name, on: model.id == chosen) { assistant.change(provider) { $0.model = model.id } }
                    }
                    if listed.isEmpty {
                        Text(assistant.listing.contains(provider.id) ? "Looking for models…" : "No models listed")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                }
            }
            .scrollIndicators(.automatic)
            .frame(maxHeight: 190)
            .fixedSize(horizontal: false, vertical: true)
        }

        private func row(_ title: String, on: Bool, pick: @escaping () -> Void) -> some View {
            PickRow(title: title, on: on) {
                pick()
                close()
            }
        }
    }

    private struct PickRow: View {
        let title: String
        let on: Bool
        let pick: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: pick) {
                HStack {
                    Text(title).font(.system(size: 12.5)).lineLimit(1)
                    Spacer(minLength: 8)
                    if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)) }
                }
                .foregroundStyle(Palette.ink.opacity(on ? 1 : 0.8))
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(hovering ? Palette.hover : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
    }

    /// Why a provider can't answer yet, in a few words.
    static func words(for status: Assistant.Status) -> String {
        switch status {
        case .ready: "ready"
        case .looking: "looking…"
        case .missing: "not installed"
        case .needsKey: "needs a key"
        case .unavailable(let reason): reason
        }
    }
}

/// Whether Return in the new tab's composer asks the assistant: a switch,
/// lit while it does. Off, Return searches with the engine.
struct AskToggle: View {
    let asks: Bool
    let engine: String
    let pick: (_ asks: Bool) -> Void

    var body: some View {
        ToolToggle(
            title: "Ask", symbol: "sparkle", on: asks, possible: true, key: "⌘J",
            help: asks
                ? "Return asks the assistant. Off, it searches with \(engine)" : "Return searches with \(engine). On, it asks the assistant"
        ) {
            pick(!asks)
        }
        .accessibilityLabel("Ask the assistant")
    }
}

/// Research, as a switch: the next question is researched in depth rather
/// than answered. Plain asking searches the web by itself when it needs to.
struct ToolToggles: View {
    private var assistant: Assistant { .shared }

    var body: some View {
        let possible = assistant.provider.searches
        ToolToggle(
            title: "Research", symbol: "binoculars", on: assistant.mode == .research, possible: possible,
            help: possible ? "Read many sources and write a report. Takes minutes" : "\(assistant.provider.name) can't search the web"
        ) {
            assistant.researching.toggle()
        }
    }
}

/// A switch among a composer's actions: a symbol and a word, on a soft
/// ground while on.
struct ToolToggle: View {
    let title: String
    let symbol: String
    let on: Bool
    let possible: Bool
    /// Its shortcut, shown faintly after the word.
    var key: String?
    let help: String
    let act: () -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            withAnimation(Motion.quick) { act() }
        } label: {
            // On the words' baseline: centred, the ⌘ sits high.
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                Text(title).font(.system(size: 12))
                if let key {
                    Text(key).font(.system(size: 11)).opacity(0.5).padding(.leading, 4)
                }
            }
            .foregroundStyle(on ? Palette.ink : hovering ? Palette.ink.opacity(0.7) : Palette.muted)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                on ? Palette.veil.opacity(1.8) : hovering ? Palette.veil : .clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!possible)
        .opacity(possible ? 1 : 0.4)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityValue(on ? "On" : "Off")
        .animation(Motion.hover, value: hovering)
    }
}
