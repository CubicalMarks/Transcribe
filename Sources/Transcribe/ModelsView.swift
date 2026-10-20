import SwiftUI
import AppKit
import TranscribeCore

struct ModelsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Image(systemName: "cpu").font(.title).foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ready for local processing").font(.title2.weight(.semibold))
                    Text("Download once. Use offline afterwards.").foregroundStyle(.secondary)
                }
            }
            Text("Transcribe downloads models and tokenizer files from Hugging Face. Audio processing stays on your Mac. Transcript text is sent only when you choose API summarisation. The first preparation can take several minutes.")
                .font(.callout).foregroundStyle(.secondary)
            VStack(spacing: 18) {
                modelRow("Whisper Turbo", subtitle: "Multilingual transcription · compressed 626 MB variant", ready: model.transcriptionReady)
                Divider()
                modelRow("SpeakerKit", subtitle: "Voice separation · Pyannote-based Core ML models", ready: model.speakersReady)
            }.padding(18).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            Toggle("Prepare speaker identification too", isOn: $model.identifySpeakers).disabled(model.isBusy)
            if model.isBusy {
                VStack(alignment: .leading, spacing: 8) {
                    if let fraction = model.fraction { ProgressView(value: fraction) } else { ProgressView().controlSize(.small) }
                    Text(model.status).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 18) {
                Link("Whisper models", destination: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml")!)
                Link("Speaker models & attribution", destination: URL(string: "https://huggingface.co/argmaxinc/speakerkit-coreml")!)
            }.font(.caption)
            Text("WhisperKit and SpeakerKit: Argmax, MIT. Whisper models: MIT. Speaker models: CC BY 4.0, derived from Pyannote; converted and quantized by Argmax. See the bundled ThirdPartyNotices for details.")
                .font(.caption2).foregroundStyle(.secondary)
            HStack {
                Button("Show Local Storage") { NSWorkspace.shared.open(model.store.root) }
                Spacer()
                if model.isBusy { Button("Cancel", action: model.cancel) }
                else {
                    Button("Download & Prepare", action: model.prepareModels).buttonStyle(.borderedProminent).disabled(model.modelsReady)
                }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 550).task { await model.refreshModels() }
    }

    private func modelRow(_ title: String, subtitle: String, ready: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Label(ready ? "Ready" : "Not prepared", systemImage: ready ? "checkmark.circle.fill" : "arrow.down.circle")
                .font(.caption).foregroundStyle(ready ? .green : .secondary)
        }
    }
}
