import SwiftUI
import TranscribeCore

struct SummaryView: View {
    @Bindable var model: AppModel

    private var endpointLabel: String {
        (try? model.summarySettings.completionURL().host) ?? "your configured API endpoint"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 18) {
                    Picker("Process", selection: $model.summarySettings.backend) {
                        ForEach(SummaryBackend.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("Preset", selection: $model.summarySettings.preset) {
                        ForEach(SummaryPreset.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                HStack {
                    Picker("Summary language", selection: $model.summarySettings.language) {
                        ForEach(SummaryLanguage.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.frame(maxWidth: 310)
                    Spacer()
                    if model.summarySettings.backend == .endpoint {
                        Button("API Settings…") { model.showSummarySettings = true }
                    }
                }
                TextField("Additional instructions (optional)", text: $model.summarySettings.extraInstructions, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...2)
                if model.summarySettings.backend == .onDevice {
                    Label(OnDeviceSummaryGenerator.unavailableReason ?? "Uses Apple's on-device model. Transcript text stays on this Mac.", systemImage: "desktopcomputer")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("Sends transcript text to \(endpointLabel). No audio is sent. Provider charges may apply.", systemImage: "network")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button(model.selected?.summary == nil ? "Summarise" : "Regenerate Summary", action: model.summarise)
                        .buttonStyle(.borderedProminent)
                        .disabled(model.selected?.segments.isEmpty != false || model.saveFailed ||
                            (model.summarySettings.backend == .onDevice && OnDeviceSummaryGenerator.unavailableReason != nil))
                    Spacer()
                    Text("Review generated notes against the transcript.").font(.caption2).foregroundStyle(.secondary)
                }
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
    }
}

struct SummarySettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = SummarySettings()
    @State private var apiKey = ""
    @State private var removeSavedKey = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Summary API settings").font(.title2.weight(.semibold))
            Text("Use an OpenAI-compatible Chat Completions endpoint. It receives transcript text only when you choose API summarisation.")
                .font(.callout).foregroundStyle(.secondary)
            Form {
                TextField("API base URL", text: $draft.baseURL, prompt: Text("https://your-provider.example/v1"))
                    .onChange(of: draft.baseURL) { _, value in
                        apiKey = ""
                        removeSavedKey = false
                    }
                TextField("Model", text: $draft.model, prompt: Text("Provider's model identifier"))
                SecureField("API key (optional)", text: $apiKey)
                    .disabled(removeSavedKey)
                Picker("Token-limit parameter", selection: $draft.tokenLimitParameter) {
                    ForEach(TokenLimitParameter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                TextField("Maximum output tokens", value: Binding(get: { draft.maximumOutputTokens ?? 4096 }, set: { draft.maximumOutputTokens = $0 }), format: .number)
            }.textFieldStyle(.roundedBorder)
            Text("Keys are stored per API URL in macOS Keychain. Leave the field blank to keep an existing key; select Remove to use that URL without authentication. Enter the key after changing the URL. Choose the token-limit parameter supported by your provider/model.")
                .font(.caption).foregroundStyle(.secondary)
            if let message { Text(message).font(.caption).foregroundStyle(.red) }
            HStack {
                Toggle("Remove saved key", isOn: $removeSavedKey)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    do {
                        _ = try draft.completionURL()
                        if removeSavedKey || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            try SummaryKeychain.save(removeSavedKey ? "" : apiKey, settings: draft)
                        }
                        // Do not overwrite preset/language selections while editing API configuration.
                        model.summarySettings.baseURL = draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        model.summarySettings.model = draft.model.trimmingCharacters(in: .whitespacesAndNewlines)
                        model.summarySettings.tokenLimitParameter = draft.tokenLimitParameter
                        model.summarySettings.maximumOutputTokens = draft.maximumOutputTokens
                        dismiss()
                    } catch { message = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }.padding(28).frame(width: 570)
            .onAppear {
                draft = model.summarySettings
            }
    }
}
