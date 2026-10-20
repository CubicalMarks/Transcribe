import SwiftUI
import TranscribeCore

struct TranscriptionProgressView: View {
    let preview: TranscriptionPreview
    let status: String
    let fraction: Double?
    let hasSavedTranscript: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(status).font(.callout.weight(.medium))
                    Spacer()
                    if let fraction { Text(fraction, format: .percent.precision(.fractionLength(0))).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                }
                if let fraction { ProgressView(value: fraction).help("Progress follows decoded audio timestamps and advances as sections finish.") }
                else { ProgressView().controlSize(.small) }
                Text(hasSavedTranscript
                    ? "Live preview · Your saved transcript is kept until this run succeeds."
                    : "Live preview · Sections appear as they finish. Text is saved when transcription completes.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 28).padding(.vertical, 18)
            if preview.segments.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "waveform").font(.system(size: 30)).foregroundStyle(.tertiary)
                    Text("Waiting for the first section…").font(.headline)
                    Text("Loading and decoding can take a moment.").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }.frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(preview.segments) { segment in
                            HStack(alignment: .top, spacing: 20) {
                                Text(Transcript.timestamp(segment.start))
                                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                                    .frame(width: 50, alignment: .leading).padding(.top, 4)
                                Text(segment.text).font(.system(size: 15)).lineSpacing(5)
                                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                            }
                        }
                    }.padding(.horizontal, 28).padding(.vertical, 18)
                }
            }
        }
    }
}
