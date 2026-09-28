import MoteAI
import SwiftUI

/// The chip naming who answers ("Claude Code · Sonnet"), with a menu to pick
/// another model or provider. Sits in the new tab's composer and the chat's.
struct ModelChip: View {
    let browser: Browser
    /// Lit, as while ⌘ is held over the new tab's composer.
    var lit = false
    /// Gets the provider ready as soon as it shows, as in a chat, where asking
    /// is certain; the new tab's waits for a sign (see `Assistant.prepare`).
    var eager = false

    @State private var hovering = false
    private var assistant: Assistant { .shared }

    var body: some View {
        let provider = assistant.provider
        Menu {
            models(of: provider)
            Divider()
            Menu("Ask With") {
                providers("On This Mac", Provider.all.filter { $0.kind != .cloud })
                providers("With an API Key", Provider.all.filter { $0.kind == .cloud })
            }
            Divider()
            Button("AI Settings…") { browser.openSettings(at: .ai) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 10.5, weight: .semibold))
                Text(label(for: provider)).font(.system(size: 12)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.6)
            }
            .foregroundStyle(lit ? Palette.ink : hovering ? Palette.ink.opacity(0.8) : Palette.muted)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.veil.opacity(lit ? 2 : hovering ? 1.4 : 0.7))
                    .strokeBorder(lit ? Palette.ink.opacity(0.2) : Palette.edge, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { inside in
            hovering = inside
            if inside { assistant.prepare() }
        }
        .help("Who answers ⌘Return — change the model or provider")
        .accessibilityLabel("Ask with \(label(for: provider))")
        .animation(Motion.hover, value: hovering)
        .animation(Motion.quick, value: lit)
        .task(id: provider.id) { if eager { assistant.prepare() } }
    }

    private func label(for provider: Provider) -> String {
        let model = assistant.model(for: provider)
        return model.isEmpty ? provider.name : "\(provider.name) · \(assistant.modelName(for: provider))"
    }

    @ViewBuilder
    private func models(of provider: Provider) -> some View {
        let chosen = assistant.model(for: provider)
        let listed = assistant.models[provider.id] ?? provider.suggested
        Section(provider.name) {
            if provider.kind == .agent {
                pick("Default Model", on: chosen.isEmpty) { assistant.change(provider) { $0.model = "" } }
            }
            ForEach(listed.prefix(40)) { model in
                pick(model.name, on: model.id == chosen) { assistant.change(provider) { $0.model = model.id } }
            }
            if listed.isEmpty {
                Text(assistant.listing.contains(provider.id) ? "Looking for models…" : "No models listed")
            }
        }
    }

    @ViewBuilder
    private func providers(_ title: String, _ list: [Provider]) -> some View {
        Section(title) {
            ForEach(list) { provider in
                let status = assistant.status(of: provider)
                let usable = status == .ready || provider.id == assistant.providerID
                pick(usable ? provider.name : "\(provider.name) — \(Self.words(for: status))", on: provider.id == assistant.providerID) {
                    assistant.providerID = provider.id
                }
                .disabled(!usable)
            }
        }
    }

    private func pick(_ title: String, on: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            if on { Label(title, systemImage: "checkmark") } else { Text(title) }
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
