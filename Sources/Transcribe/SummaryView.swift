import SwiftUI
import AppKit
import TranscribeCore

struct SummaryView: View {
    @Bindable var model: AppModel
    @State private var showInstructions = false

    private var destination: String {
        if model.summarySettings.backend == .onDevice {
            return OnDeviceSummaryGenerator.unavailableReason == nil ? "On this Mac" : "On-device model unavailable"
        }
        guard let host = try? model.summarySettings.completionURL().host else { return "Choose a provider in Settings" }
        return "Text sent to \(model.summarySettings.provider == .openAI ? "OpenAI" : host)"
    }

    private var providerReady: Bool {
        if model.summarySettings.backend == .onDevice { return OnDeviceSummaryGenerator.unavailableReason == nil }
        return (try? model.summarySettings.completionURL()) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    Picker("Preset", selection: $model.summarySettings.preset) {
                        ForEach(SummaryPreset.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.frame(maxWidth: 260)
                    Picker("Language", selection: $model.summarySettings.language) {
                        ForEach(SummaryLanguage.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.frame(maxWidth: 230)
                    Spacer(minLength: 0)
                    Button(model.selected?.summary == nil ? "Summarise" : "Regenerate", action: model.summarise)
                        .buttonStyle(.borderedProminent).fixedSize()
                        .disabled(model.selected?.segments.isEmpty != false || model.saveFailed || !providerReady)
                }
                DisclosureGroup("Additional instructions", isExpanded: $showInstructions) {
                    TextField("What should the summary focus on?", text: $model.summarySettings.extraInstructions, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(1...3).padding(.top, 6)
                }.font(.caption).foregroundStyle(.secondary)
                HStack {
                    Label(destination, systemImage: model.summarySettings.backend == .onDevice ? "desktopcomputer" : "network")
                        .help(model.summarySettings.backend == .onDevice
                            ? OnDeviceSummaryGenerator.unavailableReason ?? "Transcript text stays on this Mac."
                            : "Only transcript text is sent. Configure the destination in Settings.")
                    Spacer()
                    SettingsLink { Label("Settings…", systemImage: "gearshape") }.buttonStyle(.borderless)
                }.font(.caption).foregroundStyle(.secondary)
            }.disabled(model.locked)
            Divider()
            if let summary = model.selected?.summary {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(summary.preset.title) · \(summary.model)").font(.caption.weight(.medium))
                        Text(summary.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.selected?.summaryIsOutdated == true {
                        Label("Transcript changed", systemImage: "arrow.clockwise").font(.caption).foregroundStyle(.orange)
                    }
                }
                TextEditor(text: Binding(get: { model.selected?.summary?.text ?? "" }, set: { value in
                    model.edit { $0.summary?.text = value }
                })).font(.system(size: 14)).scrollContentBackground(.hidden)
                    .disabled(model.locked).accessibilityLabel("Editable summary")
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "text.badge.star").font(.system(size: 30)).foregroundStyle(.tertiary)
                    Text("Turn your transcript into useful notes").font(.headline)
                    Text("Choose a preset and summarise. Your transcript is kept.").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }.frame(maxWidth: .infinity)
            }
        }.padding(.horizontal, 26).padding(.bottom, 20)
            .onAppear { showInstructions = !model.summarySettings.extraInstructions.isEmpty }
    }
}

struct SummarySettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = SummarySettings()
    @State private var apiKey = ""
    @State private var removeSavedKey = false
    @State private var showAdvanced = false
    @State private var message: String?
    @State private var keyStatus = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Summarisation").font(.title2.weight(.semibold)).padding(.horizontal, 24).padding(.top, 24)
            Form {
                Section {
                    Picker("Provider", selection: Binding(get: { draft.provider }, set: { draft.useProvider($0) })) {
                        ForEach(SummaryProvider.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if draft.backend == .onDevice {
                        Text(OnDeviceSummaryGenerator.unavailableReason ?? "Uses Apple's on-device model. Transcript text stays on this Mac.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                if draft.backend == .endpoint {
                    Section {
                        if draft.provider == .custom {
                            TextField("API base URL", text: $draft.baseURL, prompt: Text("https://your-provider.example/v1"))
                        }
                        TextField("Model", text: $draft.model, prompt: Text("Model identifier"))
                        SecureField("API key", text: $apiKey, prompt: Text("Enter key, or leave blank to keep saved key"))
                            .disabled(removeSavedKey)
                        Text(keyStatus).font(.caption).foregroundStyle(.secondary)
                    } footer: {
                        Text("The key is stored per API URL in macOS Keychain. A blank field keeps an existing key.")
                    }
                    Section {
                        DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                            if draft.provider == .openAI {
                                LabeledContent("API base URL", value: draft.baseURL)
                            }
                            Picker("Token-limit parameter", selection: $draft.tokenLimitParameter) {
                                ForEach(TokenLimitParameter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            TextField("Maximum output tokens", value: Binding(get: { draft.maximumOutputTokens ?? 4096 }, set: { draft.maximumOutputTokens = $0 }), format: .number)
                            Toggle("Remove saved key on Save", isOn: $removeSavedKey)
                        }
                    }
                    Section {
                        Text("Only transcript text is sent to \((try? draft.completionURL().host) ?? "the configured endpoint"). No audio is uploaded. Provider charges may apply.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.formStyle(.grouped).disabled(model.locked)
                .onChange(of: draft.baseURL) { _, _ in apiKey = ""; removeSavedKey = false; refreshKeyStatus() }
                .onChange(of: draft.model) { _, _ in refreshKeyStatus() }
            if let message { Text(message).font(.caption).foregroundStyle(.red).padding(.horizontal, 24).padding(.bottom, 12) }
            if model.locked {
                Text("Settings can be changed when processing finishes.").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Changes", action: save).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(model.locked)
            }.padding(20)
        }.frame(width: 570, height: 550)
            .onAppear { draft = model.summarySettings; apiKey = ""; removeSavedKey = false; message = nil; refreshKeyStatus() }
    }

    private func refreshKeyStatus() {
        guard (try? draft.completionURL()) != nil else { keyStatus = "Enter the API URL and model to check for a saved key."; return }
        do { keyStatus = try SummaryKeychain.hasSavedKey(draft) ? "A key is saved for this API URL. Its validity is checked when summarising." : "No key is saved for this API URL." }
        catch { keyStatus = error.localizedDescription }
    }

    private func save() {
        guard !model.locked else { return }
        do {
            var updated = model.summarySettings
            updated.backend = draft.backend
            if draft.backend == .endpoint {
                _ = try draft.completionURL()
                if removeSavedKey || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    try SummaryKeychain.save(removeSavedKey ? "" : apiKey, settings: draft)
                }
                updated.apiPreset = draft.apiPreset
                updated.baseURL = draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                updated.model = draft.model.trimmingCharacters(in: .whitespacesAndNewlines)
                updated.tokenLimitParameter = draft.tokenLimitParameter
                updated.maximumOutputTokens = draft.maximumOutputTokens
            }
            model.summarySettings = updated
            apiKey = ""
            dismiss()
        } catch { message = error.localizedDescription }
    }
}
