import SwiftUI
import AppKit
import TranscribeCore

// Summary options occupy the same header position as transcription options.
struct SummaryOptionsView: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @State private var showInstructions = false

    private var destination: String {
        if model.summarySettings.backend == .onDevice {
            return OnDeviceSummaryGenerator.unavailableReason == nil ? "On this Mac" : "On-device model unavailable"
        }
        if model.summarySettings.backend == .chatGPT { return "Using ChatGPT plan · text sent to OpenAI" }
        guard let host = try? model.summarySettings.completionURL().host else { return "Choose a provider in Settings" }
        return "Text sent to \(model.summarySettings.provider == .openAI ? "OpenAI" : host)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Picker("Preset", selection: $model.summarySettings.preset) {
                    ForEach(SummaryPreset.allCases, id: \.self) { Text($0.title).tag($0) }
                }.frame(width: 230)
                Picker("Language", selection: $model.summarySettings.language) {
                    ForEach(SummaryLanguage.allCases, id: \.self) { Text($0.title).tag($0) }
                }.frame(width: 230)
                Spacer(minLength: 0)
                Button {
                    model.settingsPage = .summaries
                    openSettings()
                } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless).help("Summary providers and accounts…")
                .accessibilityLabel("Summary provider settings")
            }
            HStack(spacing: 12) {
                Button { showInstructions.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showInstructions ? "chevron.down" : "chevron.right")
                        Text("Additional instructions")
                        if !model.summarySettings.extraInstructions.isEmpty { Image(systemName: "circle.fill").font(.system(size: 6)) }
                    }
                }.buttonStyle(.plain).fixedSize()
                    .accessibilityValue(showInstructions ? "Expanded" : "Collapsed")
                Spacer(minLength: 0)
                Label(destination, systemImage: model.summarySettings.backend == .onDevice ? "desktopcomputer" : "network")
                    .lineLimit(1).truncationMode(.middle)
                    .help(destination + ". " + (model.summarySettings.backend == .onDevice
                        ? OnDeviceSummaryGenerator.unavailableReason ?? "Transcript text stays on this Mac."
                        : "Only transcript text is sent. No audio is uploaded. Configure the destination in Settings."))
            }.font(.body).foregroundStyle(.secondary)
            if showInstructions {
                TextField("What should the summary focus on?", text: $model.summarySettings.extraInstructions, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...3)
            }
        }.onAppear { showInstructions = !model.summarySettings.extraInstructions.isEmpty }
    }
}

// Both documents use a growing plain text field in the shared scroll area.
struct RecordingTextField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        TextField(title, text: $text, axis: .vertical)
            .textFieldStyle(.plain).font(.system(size: 16)).lineSpacing(5)
    }
}

struct SummaryContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        if let summary = model.selected?.summary {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 8) {
                    Text(summary.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    Text("·")
                    Text(summary.model)
                    Text("·")
                    Text(summary.preset.title)
                }.font(.body).foregroundStyle(.secondary)
                RecordingTextField(title: "Summary", text: Binding(get: { model.selected?.summary?.text ?? "" }, set: { value in
                    model.edit { $0.summary?.text = value }
                })).disabled(model.locked).accessibilityLabel("Editable summary")
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
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
    @State private var initialized = false

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
                            .font(.body).foregroundStyle(.secondary)
                    }
                }
                if draft.backend == .chatGPT {
                    chatGPTSettings
                }
                if draft.backend == .endpoint {
                    Section {
                        if draft.provider == .custom {
                            TextField("API base URL", text: $draft.baseURL, prompt: Text("https://your-provider.example/v1"))
                        }
                        TextField("Model", text: $draft.model, prompt: Text("Model identifier"))
                        SecureField("API key", text: $apiKey, prompt: Text("Enter key, or leave blank to keep saved key"))
                            .disabled(removeSavedKey)
                        Text(keyStatus).font(.body).foregroundStyle(.secondary)
                    } footer: {
                        Text("The key is stored per API URL in macOS Keychain. A blank field keeps an existing key.").font(.body)
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
                            .font(.body).foregroundStyle(.secondary)
                    }
                }
            }.formStyle(.grouped).disabled(model.locked)
                .onChange(of: draft.backend) { _, backend in
                    if backend == .chatGPT { model.chatGPT.loadModels(accountID: draft.chatGPTAccountID) }
                }
                .onChange(of: model.chatGPT.connectedAccountID) { _, id in
                    if let id { draft.chatGPTAccountID = id; model.chatGPT.loadModels(accountID: id) }
                }
                .onChange(of: draft.chatGPTAccountID) { _, id in
                    model.chatGPT.loadModels(accountID: id)
                }
                .onChange(of: model.chatGPT.modelsAccountID) { _, id in
                    if id == draft.chatGPTAccountID, !model.chatGPT.models.contains(where: { $0.slug == draft.chatGPTModel }) {
                        draft.chatGPTModel = model.chatGPT.models.first?.slug
                    }
                }
                .onChange(of: draft.baseURL) { _, _ in apiKey = ""; removeSavedKey = false; refreshKeyStatus() }
                .onChange(of: draft.model) { _, _ in refreshKeyStatus() }
            if let message { Text(message).font(.body).foregroundStyle(.red).padding(.horizontal, 24).padding(.bottom, 12) }
            if model.locked {
                Text("Settings can be changed when processing finishes.").font(.body).foregroundStyle(.secondary).padding(.horizontal, 24)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.chatGPT.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Changes", action: save).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(model.locked || model.chatGPT.busy)
            }.padding(20)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                guard !initialized else { return }
                initialized = true
                draft = model.summarySettings
                refreshKeyStatus()
                await model.chatGPT.load()
                if draft.backend == .chatGPT { model.chatGPT.loadModels(accountID: draft.chatGPTAccountID) }
            }
    }

    @ViewBuilder private var chatGPTSettings: some View {
        Section {
            Picker("Account", selection: $draft.chatGPTAccountID) {
                Text("Choose an account").tag(String?.none)
                ForEach(model.chatGPT.accounts) { account in
                    Text(account.displayName + (account.tokens == nil ? " (signed out)" : "")).tag(Optional(account.id))
                }
            }.disabled(model.chatGPT.busy)
            if let account = model.chatGPT.accounts.first(where: { $0.id == draft.chatGPTAccountID }) {
                Text(account.tokens == nil ? "Signed out" : account.planEnabled ? "ChatGPT plan usage enabled" : "ChatGPT plan usage not enabled")
                    .font(.body).foregroundStyle(.secondary)
                HStack {
                    Button(account.planEnabled || account.tokens == nil ? "Reconnect" : "Enable plan usage") { model.chatGPT.connect(accountID: account.id) }
                    if account.tokens != nil { Button("Sign Out") { model.chatGPT.signOut(account.id) } }
                }.disabled(model.chatGPT.busy)
            }
            if model.chatGPT.busy {
                HStack {
                    ProgressView().controlSize(.small)
                    if model.chatGPT.signingIn { Button("Cancel Sign-in", action: model.chatGPT.cancel) }
                }
            } else {
                Button("Continue with ChatGPT") { model.chatGPT.connect(accountID: nil) }
                    .help("Connect another ChatGPT account or workspace.")
                if model.chatGPT.pendingClientID != nil {
                    Button("Retry Previous Sign-in") { model.chatGPT.connect(accountID: nil, retryPending: true) }
                        .help("Reuse the previous registration after an interrupted code exchange.")
                }
            }
            if let message = model.chatGPT.message { Text(message).font(.body).foregroundStyle(.secondary) }
        } footer: {
            Text("Connect an eligible ChatGPT Plus or Pro plan. Account connections are saved when sign-in finishes; Save Changes applies your provider and model choice.").font(.body)
        }
        Section {
            if model.chatGPT.modelsAccountID == draft.chatGPTAccountID, !model.chatGPT.models.isEmpty {
                Picker("Model", selection: $draft.chatGPTModel) {
                    ForEach(model.chatGPT.models) { Text($0.display_name).tag(Optional($0.slug)) }
                }
            } else { Text("Connect an account with plan usage enabled to choose a model.").font(.body).foregroundStyle(.secondary) }
            Button("Refresh Models") { model.chatGPT.loadModels(accountID: draft.chatGPTAccountID) }.disabled(model.chatGPT.busy)
        }
        Section {
            Link("Manage ChatGPT Usage", destination: URL(string: "https://chatgpt.com/settings/usage")!)
            Text("Summaries use your existing ChatGPT plan limits or available credits. Only transcript text is sent to OpenAI; audio stays on this Mac. No automatic switch to API billing.")
                .font(.body).foregroundStyle(.secondary)
        }
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
            if draft.backend == .chatGPT {
                guard let account = model.chatGPT.accounts.first(where: { $0.id == draft.chatGPTAccountID }), account.planEnabled,
                      model.chatGPT.modelsAccountID == account.id,
                      model.chatGPT.models.contains(where: { $0.slug == draft.chatGPTModel }) else {
                    throw TranscribeError.message("Connect your ChatGPT plan and choose an available model before saving.")
                }
                updated.chatGPTAccountID = account.id
                updated.chatGPTModel = draft.chatGPTModel
            }
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
