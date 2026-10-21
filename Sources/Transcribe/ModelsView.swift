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
                    Picker("Model", selection: $model.transcriptionModel) {
                        ForEach(TranscriptionModel.allCases, id: \.self) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }.disabled(model.locked)
                    modelRow(model.transcriptionModel.title, subtitle: model.transcriptionModel.detail, ready: model.transcriptionReady)
                    if model.transcriptionModel == .pianissimo {
                        Text("Swedish only. Use Whisper for English or mixed recordings. This experimental conversion has not been validated on natural meetings. Custom vocabulary is not available in this integration.")
                            .font(.body).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Transcription")
                } footer: {
                    Text("Selection applies to the next transcription. Existing transcripts and downloaded models are kept.")
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
                    Button("Download & Prepare", action: model.prepareModels).buttonStyle(.borderedProminent).disabled(model.locked || model.modelsReady)
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
