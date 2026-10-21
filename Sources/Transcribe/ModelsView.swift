import SwiftUI
import AppKit
import TranscribeCore

struct ModelsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAttribution = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Local models").font(.title2.weight(.semibold)).padding(.horizontal, 24).padding(.top, 24)
            Form {
                Section {
                    Picker("Default model", selection: $model.transcriptionPreferences.defaultModel) {
                        ForEach(TranscriptionModel.allCases.filter { $0.supports(language: nil) }, id: \.self) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }.disabled(model.locked)
                    Picker("Swedish model", selection: Binding(get: {
                        model.transcriptionPreferences.languageModels["sv"]
                    }, set: { model.transcriptionPreferences.languageModels["sv"] = $0 })) {
                        Text("Use default").tag(TranscriptionModel?.none)
                        ForEach(TranscriptionModel.allCases.filter { $0.supports(language: "sv") }, id: \.self) { choice in
                            Text(choice.title).tag(Optional(choice))
                        }
                    }.disabled(model.locked)
                    Picker("New recording language", selection: $model.transcriptionPreferences.defaultLanguage) {
                        Text("Remember last selected").tag("last")
                        Text("Automatic / mixed").tag("auto")
                        Text("Swedish").tag("sv")
                        Text("English").tag("en")
                        Divider()
                        ForEach(LocalSpeechEngine.languages.filter { !["sv", "en"].contains($0.code) }, id: \.code) { language in
                            Text(language.name).tag(language.code)
                        }
                    }.disabled(model.locked)
                } header: {
                    Text("Transcription")
                } footer: {
                    Text("Automatic and languages without an override use the default model. New recordings and imports start with the language preference above; each recording keeps its own selection.")
                }
                Section {
                    ForEach(TranscriptionModel.allCases.filter { model.transcriptionPreferences.configuredModels.contains($0) }, id: \.self) { choice in
                        modelRow(choice.title, subtitle: choice.detail, ready: model.isPrepared(choice))
                    }
                    if model.transcriptionPreferences.configuredModels.contains(.pianissimo) {
                        Text("Pianissimo is experimental and Swedish-only. Custom vocabulary is not available.")
                            .font(.body).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Configured models")
                }
                Section {
                    modelRow("SpeakerKit", subtitle: "Voice separation · Pyannote-based Core ML models", ready: model.speakersReady)
                    Toggle("Prepare speaker identification too", isOn: $model.identifySpeakers).disabled(model.locked)
                } header: {
                    Text("Speaker identification")
                } footer: {
                    Text("Download once from Hugging Face, then transcribe offline. Audio processing stays on your Mac. First preparation can take several minutes.")
                        .font(.body)
                }
                Section {
                    Button("Show Local Storage") { NSWorkspace.shared.open(model.store.root) }
                    DisclosureGroup("Models and attribution", isExpanded: $showAttribution) {
                        Link("Whisper models", destination: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml")!)
                        Link("Speaker models & attribution", destination: URL(string: "https://huggingface.co/argmaxinc/speakerkit-coreml")!)
                        Link("Pianissimo Core ML conversion", destination: URL(string: "https://huggingface.co/magnushjelm/pianissimo-sv-coreml")!)
                        Text("WhisperKit and SpeakerKit: MIT. FluidAudio: Apache 2.0. Whisper models: MIT. Speaker models: CC BY 4.0, derived from Pyannote; converted by Argmax. Pianissimo: Klang AI, based on NVIDIA Parakeet v3, CC BY 4.0; Core ML conversion by magnushjelm with 8-bit encoder compression. See the bundled ThirdPartyNotices for details.")
                            .font(.body).foregroundStyle(.secondary)
                    }
                }
            }.formStyle(.grouped)
            if model.isBusy {
                VStack(alignment: .leading, spacing: 8) {
                    if let fraction = model.fraction { ProgressView(value: fraction) } else { ProgressView().controlSize(.small) }
                    Text(model.status).font(.body).foregroundStyle(.secondary)
                }.padding(.horizontal, 24).padding(.bottom, 12)
            }
            HStack {
                if model.isBusy { Button("Cancel Processing", action: model.cancel) }
                else {
                    Button("Prepare Configured Models", action: model.prepareModels).buttonStyle(.borderedProminent).disabled(model.locked || model.configuredModelsReady)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(20)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).task { await model.refreshModels() }
    }

    private func modelRow(_ title: String, subtitle: String, ready: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(subtitle).font(.body).foregroundStyle(.secondary)
            }
            Spacer()
            Label(ready ? "Ready" : "Not prepared", systemImage: ready ? "checkmark.circle.fill" : "arrow.down.circle")
                .font(.body).foregroundStyle(ready ? .green : .secondary)
        }.padding(.vertical, 4)
    }
}
