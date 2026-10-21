import SwiftUI
import AppKit
import TranscribeCore

struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @State private var dropTarget = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform").font(.title2).foregroundStyle(.indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transcribe").font(.headline)
                        Text("Your local library").font(.body).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(20)
                List(selection: Binding(get: { model.selectedID }, set: { model.select($0) })) {
                    Section("Recordings") {
                        ForEach(model.projects) { project in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: project.segments.isEmpty ? "waveform" : "text.alignleft")
                                    .foregroundStyle(.indigo).padding(.top, 3)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(project.title).font(.system(size: 14, weight: .medium)).lineLimit(2)
                                    Text(project.createdAt, format: .dateTime.month(.abbreviated).day())
                                        .font(.body).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Text(Transcript.timestamp(project.duration)).font(.body.monospacedDigit()).foregroundStyle(.secondary)
                            }.padding(.vertical, 6).tag(project.id)
                                .contextMenu {
                                    Button("Rename…") { model.renameRecording(project.id) }
                                    Button("Move to Trash…", role: .destructive) { model.deleteRecording(project.id) }
                                }
                        }
                    }
                }.listStyle(.sidebar).disabled(model.locked || model.saveFailed)
                    .onDeleteCommand { model.deleteRecording() }
                Divider()
                HStack {
                    Label("On this Mac", systemImage: "internaldrive").font(.body).foregroundStyle(.secondary)
                    Spacer()
                    Button { model.deleteRecording() } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).help("Move selected recording to Trash…")
                        .accessibilityLabel("Move selected recording to Trash")
                        .disabled(!model.canManageRecording)
                    SettingsLink { Image(systemName: "slider.horizontal.3") }
                        .buttonStyle(.plain).help("Settings: local models and summarisation")
                }.padding(16)
            }.navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            VStack(spacing: 0) {
                if model.isRecording { recording }
                else if let transcript = model.selected { project(transcript) }
                else { welcome }
                Divider()
                footer
            }
            .background(Color(nsColor: .textBackgroundColor))
            .overlay {
                if dropTarget {
                    RoundedRectangle(cornerRadius: 14).fill(.indigo.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.indigo, style: StrokeStyle(lineWidth: 2, dash: [8])))
                        .padding(12).allowsHitTesting(false)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard !model.locked, !model.saveFailed, let url = urls.first, url.isFileURL else { return false }
                model.importAudio(url)
                return true
            } isTargeted: { dropTarget = $0 }
        }
        .tint(.indigo)
        .toolbar {
            ToolbarItemGroup {
                Button(action: model.openFile) { Label("Import Audio", systemImage: "plus") }.disabled(model.locked || model.saveFailed)
                Button(action: model.startRecording) { Label("Record", systemImage: "mic") }.disabled(model.locked || model.saveFailed)
                Button { model.showModels = true } label: { Label("Models", systemImage: "cpu") }
            }
        }
        .onChange(of: model.showModels) { _, requested in
            if requested {
                model.settingsPage = .models
                openSettings()
                model.showModels = false
            }
        }
        .alert("Transcribe", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 25).fill(.indigo.opacity(0.08)).frame(width: 96, height: 96)
                Image(systemName: "waveform").font(.system(size: 43, weight: .medium)).foregroundStyle(.indigo)
            }
            VStack(spacing: 10) {
                Text("A conversation, in words.").font(.system(size: 29, weight: .semibold, design: .rounded))
                Text("Record a conversation or bring your own audio.\nTranscribe and identify speakers, entirely on your Mac.")
                    .font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
            }
            VStack(spacing: 18) {
                Image(systemName: "arrow.down.doc").font(.system(size: 27)).foregroundStyle(.secondary)
                VStack(spacing: 5) {
                    Text("Drop an audio file here").font(.headline)
                    Text("M4A, AAC, MP3, WAV and other supported audio").font(.body).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Button("Open Audio…", action: model.openFile).buttonStyle(.borderedProminent).controlSize(.large)
                    Button(action: model.startRecording) { Label("Record", systemImage: "mic.fill") }
                        .buttonStyle(.bordered).controlSize(.large)
                }
            }.frame(maxWidth: 450).padding(30)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [5])))
            options.padding(.horizontal, 25).frame(maxWidth: 570)
            Label("Private by design. No audio uploads.", systemImage: "lock.shield")
                .font(.body).foregroundStyle(.secondary)
            Spacer()
        }.padding(30).frame(maxWidth: .infinity).disabled(model.isBusy)
    }

    private var options: some View {
        TranscriptionOptionsLayout {
            transcriptionLanguage
            HStack(spacing: 16) { speakerOptions }
        }
    }

    private var transcriptionLanguage: some View {
        Picker("Language", selection: $model.language) {
            Text("Automatic").tag("auto")
            Text("Swedish").tag("sv")
            Text("English").tag("en")
            Divider()
            ForEach(LocalSpeechEngine.languages.filter { !["sv", "en"].contains($0.code) }, id: \.code) { language in
                Text(language.name).tag(language.code)
            }
        }.frame(width: 220)
            .help("For mixed recordings, use Automatic. The model follows your language rules in Settings → Local Models. Current model: \(model.transcriptionModel.title).")
    }

    @ViewBuilder private var speakerOptions: some View {
        Toggle("Identify speakers", isOn: $model.identifySpeakers).toggleStyle(.switch).controlSize(.small).fixedSize()
            .help("Separate voices within this recording. Speaker labels can be renamed after transcription.")
        if model.identifySpeakers {
            Picker("Count", selection: $model.expectedSpeakers) {
                Text("Automatic").tag(0)
                ForEach(1...12, id: \.self) { Text("\($0)").tag($0) }
            }.frame(width: 160).help("Expected number of speakers. Automatic estimates the count.")
        }
    }

    private func project(_ transcript: Transcript) -> some View {
        let speakerIDs = transcript.speakerIDs
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Title", text: Binding(get: { model.selected?.title ?? "" }, set: { value in model.edit { $0.title = value } }))
                            .textFieldStyle(.plain).font(.system(size: 25, weight: .semibold)).disabled(model.locked)
                        HStack(spacing: 8) {
                            Text(transcript.createdAt, format: .dateTime.month(.wide).day().year())
                            Text("·")
                            Text(Transcript.timestamp(model.playerDuration > 0 ? model.playerDuration : transcript.duration))
                            if let language = transcript.language { Text("·"); Text(Locale.current.localizedString(forLanguageCode: language) ?? language) }
                        }.font(.body).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("Audio local", systemImage: "lock.fill").font(.body.weight(.medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 6).background(.quaternary, in: Capsule())
                }
                PlaybackView(model: model)
                Group {
                    if model.showSummary { SummaryOptionsView(model: model) }
                    else { options }
                }.disabled(model.locked)
            }.padding(26)
            Divider()
            HStack {
                Picker("View", selection: $model.showSummary) {
                    Text("Transcript").tag(false)
                    Text("Summary").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 200)
                if !model.showSummary, let preview = model.transcriptionPreview {
                    Text(preview.segments.isEmpty ? "Live preview" : "\(preview.segments.count) sections ready")
                        .font(.body).foregroundStyle(.secondary)
                } else if model.showSummary, transcript.summary != nil {
                    if transcript.summaryIsOutdated {
                        Label("Transcript changed", systemImage: "arrow.clockwise")
                            .font(.body).foregroundStyle(.orange)
                            .help("Review or regenerate the summary after editing the transcript.")
                    }
                } else if !transcript.segments.isEmpty, !model.showSummary {
                    Text("\(transcript.segments.count) segments").font(.body).foregroundStyle(.secondary)
                }
                Spacer()
                if !transcript.segments.isEmpty {
                    if transcript.speakersIdentified, !model.showSummary {
                        SpeakerNamesButton(model: model)
                    }
                    Menu {
                        if model.showSummary {
                            Button("Copy Summary", action: model.copySummary).disabled(transcript.summary == nil)
                            ForEach(ExportFormat.allCases, id: \.self) { format in
                                Button("Export Summary as \(format.title)…") { model.exportSummary(format) }.disabled(transcript.summary == nil)
                            }
                        } else {
                            Button("Copy Transcript", action: model.copyTranscript)
                            ForEach(ExportFormat.allCases, id: \.self) { format in
                                Button("Export \(format.title)…") { model.export(format) }
                            }
                        }
                    } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .disabled(!model.showSummary && model.transcriptionPreview != nil)
                }
            }.padding(.horizontal, 26).padding(.vertical, 14)
            if !model.showSummary, let preview = model.transcriptionPreview {
                TranscriptionProgressView(preview: preview, status: model.status, fraction: model.fraction,
                    hasSavedTranscript: !transcript.segments.isEmpty)
            } else if model.showSummary ? transcript.summary == nil : transcript.segments.isEmpty {
                documentEmptyState(transcript)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if model.showSummary { SummaryContentView(model: model) }
                        else {
                            ForEach(transcript.segments) { segment in segmentRow(segment, transcript: transcript, speakerIDs: speakerIDs) }
                        }
                    }.padding(.horizontal, 28).padding(.vertical, 18)
                }
                HStack(spacing: 16) {
                    if model.showSummary {
                        Button("Regenerate Summary", action: model.summarise).disabled(!model.summaryProviderReady)
                    } else {
                        Button("Transcribe Again", action: model.transcribe)
                        Button(transcript.speakersIdentified ? "Identify Speakers Again" : "Identify Speakers", action: model.addSpeakers)
                    }
                    Spacer()
                    if model.showSummary {
                        if transcript.canRestorePreviousSummary {
                            Button("Restore Previous Summary", action: model.restorePreviousResult)
                                .help("Restore the summary from before the last run, replacing current summary edits.")
                        }
                    } else {
                        if transcript.canRestorePreviousTranscription {
                            Button("Restore Previous Transcript", action: model.restorePreviousResult)
                                .help("Restore text and speaker labels from before the last run, replacing current transcript edits.")
                        }
                    }
                }.buttonStyle(.borderless).font(.body).padding(20).disabled(model.locked || model.saveFailed)
            }
        }
    }

    private func documentEmptyState(_ transcript: Transcript) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: model.showSummary ? "text.badge.star" : "text.bubble")
                .font(.system(size: 36)).foregroundStyle(.secondary)
            Text(model.showSummary ? "Ready to summarise" : "Ready when you are").font(.title3.weight(.medium))
            Text(model.showSummary
                ? transcript.segments.isEmpty ? "Transcribe this recording before creating a summary." : "Choose a preset and language, then summarise your transcript."
                : "Your audio is saved. Choose a language and transcribe.")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if model.showSummary, transcript.segments.isEmpty {
                Button("Show Transcript") { model.showSummary = false }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.locked)
            } else {
                Button(model.showSummary ? "Summarise" : "Transcribe") {
                    if model.showSummary { model.summarise() } else { model.transcribe() }
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(model.locked || model.saveFailed || (model.showSummary && !model.summaryProviderReady))
            }
            Spacer()
            if model.showSummary ? transcript.canRestorePreviousSummary : transcript.canRestorePreviousTranscription {
                HStack {
                    Spacer()
                    Button(model.showSummary ? "Restore Previous Summary" : "Restore Previous Transcript", action: model.restorePreviousResult)
                }.buttonStyle(.borderless).font(.body).padding(.bottom, 20)
                    .disabled(model.locked || model.saveFailed)
            }
        }.padding(.horizontal, 28).frame(maxWidth: .infinity)
    }

    private func segmentRow(_ segment: TranscriptSegment, transcript: Transcript, speakerIDs: [Int]) -> some View {
        HStack(alignment: .top, spacing: 20) {
            Button { model.seek(segment.start, play: true) } label: {
                Text(Transcript.timestamp(segment.start)).font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
            }.buttonStyle(.plain).frame(width: 64, alignment: .leading).padding(.top, 4)
                .help("Play from this timestamp.")
            VStack(alignment: .leading, spacing: 7) {
                if transcript.speakersIdentified {
                    Menu {
                        ForEach(speakerIDs, id: \.self) { id in
                            Button(transcript.speakerName(id)) {
                                model.edit { item in
                                    if let index = item.segments.firstIndex(where: { $0.id == segment.id }) { item.segments[index].speakerID = id; item.textEdited = true }
                                }
                            }
                        }
                        Button("Unassigned") {
                            model.edit { item in
                                if let index = item.segments.firstIndex(where: { $0.id == segment.id }) { item.segments[index].speakerID = nil; item.textEdited = true }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(speakerColor(segment.speakerID)).frame(width: 6, height: 6)
                            Text(transcript.speakerName(segment.speakerID)).font(.system(size: 13, weight: .semibold))
                        }
                    }.menuStyle(.borderlessButton).fixedSize().disabled(model.locked)
                }
                RecordingTextField(title: "Transcript at \(Transcript.timestamp(segment.start))", text: Binding(get: {
                    segment.text
                }, set: { value in
                    model.edit { item in
                        if let index = item.segments.firstIndex(where: { $0.id == segment.id }) { item.segments[index].text = value; item.textEdited = true }
                    }
                })).disabled(model.locked)
                .accessibilityLabel("Transcript at \(Transcript.timestamp(segment.start))")
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var recording: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "mic.fill").font(.system(size: 42)).foregroundStyle(.red)
            VStack(spacing: 10) {
                Text(model.isPaused ? "Recording paused" : "Listening…").font(.title.weight(.semibold))
                Text(Transcript.timestamp(model.recordingSeconds)).font(.system(size: 44, weight: .light, design: .monospaced))
            }
            ProgressView(value: model.recordingLevel).tint(.red).frame(width: 280).accessibilityLabel("Microphone level")
            HStack(spacing: 14) {
                Button(model.isPaused ? "Resume" : "Pause", action: model.togglePause).controlSize(.large)
                Button("Stop & Transcribe") { model.stopRecording() }.buttonStyle(.borderedProminent).controlSize(.large)
                Button("Stop & Save") { model.stopRecording(transcribeAfter: false) }.controlSize(.large)
            }
            Text("Microphone only · Audio saved on this Mac\nMake sure everyone knows you are recording.")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
            Spacer()
        }.frame(maxWidth: .infinity).padding(30)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if model.isBusy {
                if let fraction = model.fraction {
                    ProgressView(value: fraction).frame(width: 95)
                    Text(fraction, format: .percent.precision(.fractionLength(0))).font(.body.monospacedDigit())
                }
                else { ProgressView().controlSize(.small) }
            } else { Image(systemName: model.saveFailed ? "exclamationmark.triangle" : "lock.shield").foregroundStyle(.secondary) }
            Text(model.status.isEmpty ? "Local processing · Models download once, audio stays here" : model.status)
                .font(.body).foregroundStyle(.secondary).lineLimit(2)
            Spacer()
            if model.saveFailed { Button("Retry Save", action: model.retrySave).controlSize(.regular) }
            if model.isBusy { Button("Cancel", action: model.cancel).controlSize(.regular) }
        }.padding(.horizontal, 20).frame(minHeight: 43)
    }

    private func speakerColor(_ id: Int?) -> Color {
        guard let id else { return .gray }
        return [.indigo, .teal, .orange, .pink, .purple, .blue][abs(id) % 6]
    }
}

// Playback updates ten times a second; keep their observation out of the document tree.
struct PlaybackView: View {
    @Bindable var model: AppModel
    var body: some View {
        HStack(spacing: 16) {
            Button(action: model.togglePlayback) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 16))
                    .frame(width: 38, height: 38).background(.indigo.opacity(0.09), in: Circle())
            }.buttonStyle(.plain).disabled(model.playerDuration <= 0).accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            VStack(spacing: 7) {
                GeometryReader { geometry in
                    WaveformView(values: model.waveform, progress: model.playerDuration > 0 ? model.playhead / model.playerDuration : 0)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            model.seek(value.location.x / max(1, geometry.size.width) * model.playerDuration)
                        })
                }.frame(height: 34)
                Slider(value: Binding(get: { model.playhead }, set: { model.seek($0) }), in: 0...max(0.01, model.playerDuration))
                    .controlSize(.regular).disabled(model.playerDuration <= 0).accessibilityLabel("Playback position")
            }
            Text("\(Transcript.timestamp(model.playhead)) / \(Transcript.timestamp(model.playerDuration))")
                .font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary).frame(width: 132)
        }.padding(14).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

}

struct WaveformView: View {
    let values: [Float]
    let progress: Double
    var body: some View {
        Canvas { context, size in
            guard !values.isEmpty else {
                var line = Path(); line.move(to: CGPoint(x: 0, y: size.height / 2)); line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(line, with: .color(.secondary.opacity(0.2)), lineWidth: 1)
                return
            }
            let step = size.width / Double(values.count)
            for (index, peak) in values.enumerated() {
                let height = max(2, Double(peak) * size.height)
                let rect = CGRect(x: Double(index) * step, y: (size.height - height) / 2, width: max(1, step - 1.5), height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(Double(index) / Double(values.count) <= progress ? .indigo : .secondary.opacity(0.3)))
            }
        }.accessibilityLabel("Audio waveform")
    }
}
