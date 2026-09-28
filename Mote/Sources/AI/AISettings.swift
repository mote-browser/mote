import AppKit
import MoteAI
import MoteCore
import SwiftUI

/// Settings › AI: who answers when asked, with which model, and what each
/// provider needs: a key, an address, or its program on the Mac.
struct AISettings: View {
    let browser: Browser
    @ObservedObject var prefs: Preferences

    @State private var keyDraft = ""
    @State private var checking = false
    @State private var checked: (provider: String, result: String)?
    private var assistant: Assistant { .shared }

    var body: some View {
        let provider = assistant.provider
        SettingsSection(
            "Asking",
            note: "In a new tab, ↩ searches with \(prefs.engine.name(custom: prefs.customEngine)) and ⌘J switches to asking the assistant."
        ) {
            SettingRow("Ask with", provider.summary, symbol: "sparkles", tint: Tint.purple) { providerPicker }
            RowRule()
            SettingRow("Model", modelDetail(provider), symbol: "cpu", tint: Tint.indigo) { ModelField(provider: provider) }
            if provider.kind == .cloud {
                RowRule()
                keyRow(provider)
            }
            if provider.movable {
                RowRule()
                AddressRow(provider: provider)
            }
            if let agent = provider.agent {
                RowRule()
                programRow(provider, agent: agent)
            }
            RowRule()
            SettingRow(
                "Search the web", provider.searches ? webDetail(provider) : "\(provider.name) can't search the web", symbol: "globe",
                tint: Tint.blue, on: Binding(get: { assistant.searchesWeb }, set: { assistant.searchesWeb = $0 })
            )
            .disabled(!provider.searches)
            RowRule()
            SettingRow("Check it works", checkDetail(provider), symbol: "checkmark.seal", tint: Tint.green) {
                if checking { Ring(size: 12) } else { Pill("Check") { check(provider) } }
            }
        }
        .id(provider.id)

        SettingsSection(
            "On this Mac",
            note:
                "Agents use their own accounts and work in a folder of Mote's own. Claude Code gets only web search and page reading; Codex runs read-only; opencode's planning agent writes no files but may run commands."
        ) {
            ForEach(Array(Provider.all.filter { $0.kind != .cloud }.enumerated()), id: \.element.id) { index, item in
                if index > 0 { RowRule() }
                ProviderRow(provider: item)
            }
            RowRule()
            SettingRow(
                "Installed something new?", "Mote looks for agents where your shell finds them", symbol: "magnifyingglass", tint: Tint.gray
            ) {
                if assistant.looking { Ring(size: 12) } else { Pill("Look Again") { Task { await assistant.lookAround(again: true) } } }
            }
        }

        SettingsSection("With an API key", note: "Keys stay in the Mac's keychain. Questions go straight to the provider you choose.") {
            ForEach(Array(Provider.all.filter { $0.kind == .cloud }.enumerated()), id: \.element.id) { index, item in
                if index > 0 { RowRule() }
                ProviderRow(provider: item)
            }
        }
        .task { await assistant.lookAround() }
    }

    // MARK: - Choosing

    private var providerPicker: some View {
        Picker(
            "",
            selection: Binding(get: { assistant.providerID }, set: { assistant.providerID = $0 })
        ) {
            Section("On This Mac") {
                ForEach(Provider.all.filter { $0.kind != .cloud }) { Text($0.name).tag($0.id) }
            }
            Section("With an API Key") {
                ForEach(Provider.all.filter { $0.kind == .cloud }) { Text($0.name).tag($0.id) }
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }

    private func webDetail(_ provider: Provider) -> String {
        provider.search == .online
            ? "Through OpenRouter every question would search, so only Research does"
            : "Looks things up when a question needs it, and cites its sources"
    }

    private func modelDetail(_ provider: Provider) -> String {
        if assistant.status(of: provider) == .needsKey { return "Add a key to see \(provider.name)'s models" }
        if let failure = assistant.listFailures[provider.id] { return failure }
        if assistant.listing.contains(provider.id) { return "Asking \(provider.name) for its models…" }
        if let count = assistant.models[provider.id]?.count, count > 0 { return "\(count) to choose from" }
        return provider.kind == .agent ? "Empty uses the agent's own default" : "The model's id, as the provider names it"
    }

    // MARK: - Keys

    @ViewBuilder
    private func keyRow(_ provider: Provider) -> some View {
        if assistant.hasKey(for: provider) {
            SettingRow("API key", "Saved in the keychain", symbol: "key", tint: Tint.yellow) {
                Pill("Remove") { assistant.setKey("", for: provider) }
            }
        } else {
            SettingRow(
                "API key", provider.needsKey ? "Needed to ask \(provider.name)" : "If the server asks for one", symbol: "key",
                tint: Tint.yellow
            ) {
                if let page = provider.keyPage {
                    Pill("Get a Key") {
                        browser.tuning = false
                        browser.open(page, foreground: true)
                    }
                }
            }
            HStack(spacing: 8) {
                SecureField("", text: $keyDraft, prompt: Text("Paste the key"))
                    .textFieldStyle(.plain)
                    .textStyle(.row)
                    .onSubmit { saveKey(provider) }
                Pill("Save", filled: !keyDraft.isEmpty) { saveKey(provider) }
                    .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Palette.ground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(EdgeInsets(top: 0, leading: 47, bottom: 10, trailing: 12))
        }
    }

    private func saveKey(_ provider: Provider) {
        guard !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if assistant.setKey(keyDraft, for: provider) {
            keyDraft = ""
            check(provider)
        } else {
            checked = (provider.id, "The keychain didn't take the key")
        }
    }

    // MARK: - Programs

    private func programRow(_ provider: Provider, agent: Provider.Agent) -> some View {
        let chosen = assistant.setup(for: provider).program?.isEmpty == false
        let detail: String =
            if let program = assistant.program(of: provider) {
                program.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            } else if assistant.found == nil {
                "Looking…"
            } else {
                "Not found. Install it with: \(agent.install)"
            }
        return SettingRow("Program", detail, symbol: "terminal", tint: Tint.gray) {
            if chosen {
                Pill("Use Found") { assistant.change(provider) { $0.program = nil } }
            } else {
                Pill("Choose…") { chooseProgram(for: provider) }
            }
        }
    }

    private func chooseProgram(for provider: Provider) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.prompt = "Use This"
        panel.message = "Choose the \(provider.agent?.program ?? "agent") program"
        if panel.runModal() == .OK, let url = panel.url { assistant.change(provider) { $0.program = url.path } }
    }

    // MARK: - Checking

    private func checkDetail(_ provider: Provider) -> String {
        if let checked, checked.provider == provider.id { return checked.result }
        switch assistant.status(of: provider) {
        case .ready: return "Asks \(provider.name) for its models"
        case .looking: return "Looking for \(provider.name)…"
        case .missing: return "\(provider.name) isn't installed"
        case .needsKey: return "Add a key first"
        case .unavailable(let reason): return reason
        }
    }

    private func check(_ provider: Provider) {
        checking = true
        checked = nil
        Task {
            assistant.forgetModels(of: provider)
            if provider.kind == .local { await assistant.checkServers() }
            let models = await assistant.listModels(of: provider)
            checking = false
            if let failure = assistant.listFailures[provider.id] {
                checked = (provider.id, failure)
            } else if assistant.status(of: provider) != .ready {
                checked = (provider.id, checkDetail(provider))
            } else {
                checked = (provider.id, models.isEmpty ? "It answered, with no models listed" : "It works — \(models.count) models")
            }
        }
    }
}

/// A provider, how it stands, and a button to use it.
private struct ProviderRow: View {
    let provider: Provider
    private var assistant: Assistant { .shared }

    var body: some View {
        let status = assistant.status(of: provider)
        SettingRow(provider.name, detail(status), symbol: symbol, tint: tint) {
            if provider.id == assistant.providerID {
                Label("In use", systemImage: "checkmark").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
            } else {
                HStack(spacing: 8) {
                    Circle().fill(status == .ready ? Palette.safe : Palette.faint).frame(width: 6, height: 6)
                        .accessibilityLabel(status == .ready ? "Ready" : "Not ready")
                    Pill("Use") { assistant.providerID = provider.id }
                        .disabled(status != .ready && status != .needsKey)
                        .opacity(status != .ready && status != .needsKey ? 0.4 : 1)
                }
            }
        }
    }

    private func detail(_ status: Assistant.Status) -> String {
        switch status {
        case .ready:
            if let program = assistant.program(of: provider) {
                return "Found at \(program.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))"
            }
            return provider.kind == .cloud && assistant.hasKey(for: provider) ? "Key saved" : provider.summary
        case .looking: return "Looking…"
        case .missing: return "Not installed"
        case .needsKey: return provider.summary
        case .unavailable(let reason): return reason
        }
    }

    private var symbol: String {
        switch provider.connection {
        case .agent: "terminal"
        case .apple: "apple.logo"
        case .openAI where provider.kind == .local: "desktopcomputer"
        default: "cloud"
        }
    }

    private var tint: Color {
        switch provider.kind {
        case .agent: Tint.orange
        case .local: provider.connection == .apple ? Tint.gray : Tint.teal
        case .cloud: Tint.blue
        }
    }
}

/// The model's id, typed or picked from what the provider lists.
private struct ModelField: View {
    let provider: Provider
    @State private var draft = ""
    private var assistant: Assistant { .shared }

    var body: some View {
        let listed = assistant.models[provider.id] ?? provider.suggested
        HStack(spacing: 4) {
            TextField("", text: $draft, prompt: Text(provider.defaultModel.isEmpty ? "Default" : provider.defaultModel))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: 170)
                .onSubmit(save)
            Menu {
                if provider.kind == .agent { Button("Default") { pick("") } }
                ForEach(listed.prefix(80)) { model in
                    Button(model.name == model.id ? model.id : "\(model.name) — \(model.id)") { pick(model.id) }
                }
                if listed.isEmpty { Text("None listed") }
            } label: {
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.muted)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Palette.hairline))
        .onAppear { draft = assistant.setup(for: provider).model ?? "" }
        .onChange(of: draft) { save() }
        .task { await assistant.listModels(of: provider) }
    }

    private func pick(_ id: String) { draft = id }

    private func save() {
        let id = draft.trimmingCharacters(in: .whitespaces)
        guard id != (assistant.setup(for: provider).model ?? "") else { return }
        assistant.change(provider) { $0.model = id.isEmpty ? nil : id }
    }
}

/// Where a movable provider is: a server on another port or another Mac.
private struct AddressRow: View {
    let provider: Provider
    @State private var draft = ""
    private var assistant: Assistant { .shared }

    var body: some View {
        SettingRow("Address", "Where the server answers", symbol: "network", tint: Tint.teal) {
            TextField("", text: $draft, prompt: Text(provider.base?.absoluteString ?? "http://"))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: 210)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Palette.ground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Palette.hairline))
                .onSubmit {
                    save()
                    Task { await assistant.checkServers() }
                }
        }
        .onAppear { draft = assistant.setup(for: provider).address ?? "" }
        .onChange(of: draft) { save() }
    }

    private func save() {
        let address = draft.trimmingCharacters(in: .whitespaces)
        guard address != (assistant.setup(for: provider).address ?? "") else { return }
        assistant.change(provider) { $0.address = address.isEmpty ? nil : address }
        assistant.forgetModels(of: provider)
    }
}
