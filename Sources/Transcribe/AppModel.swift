import AppKit
import AVFoundation
import Observation
import UniformTypeIdentifiers
import TranscribeCore

@MainActor @Observable
final class AppModel: NSObject, AVAudioRecorderDelegate {
    let store: TranscriptStore
    let engine: LocalSpeechEngine
    let pianissimo: PianissimoEngine
    var transcriptionModel = TranscriptionModel.whisperTurbo {
        didSet {
            UserDefaults.standard.set(transcriptionModel.rawValue, forKey: "transcriptionModel")
            if transcriptionModel == .pianissimo { language = "sv" }
        }
    }
    var projects: [Transcript] = []
    var selectedID: UUID?
    var language = "auto"
    var identifySpeakers = true
    var expectedSpeakers = 0
    var isBusy = false
    var status = ""
    var fraction: Double?
    var transcriptionPreview: TranscriptionPreview?
    var errorMessage: String?
    var showModels = false
    var settingsPage = SettingsPage.models
    var showSummary = false
    let chatGPT = ChatGPTConnection()
    var summarySettings = SummarySettings() {
        didSet {
            if let data = try? JSONEncoder().encode(summarySettings) {
                UserDefaults.standard.set(data, forKey: "summarySettings")
            }
        }
    }
    var whisperReady = false
    var pianissimoReady = false
    var transcriptionReady: Bool { transcriptionModel == .whisperTurbo ? whisperReady : pianissimoReady }
    var speakersReady = false
    var isRecording = false
    var isPaused = false
    var recordingSeconds: Double = 0
    var recordingLevel: Double = 0
    var isPlaying = false
    var playhead: Double = 0
    var playerDuration: Double = 0
    var waveform: [Float] = []
    var saveFailed = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var operationID: UUID?
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var timer: Timer?

    var selected: Transcript? { projects.first { $0.id == selectedID } }
    var locked: Bool { isBusy || isRecording }
    var modelsReady: Bool { transcriptionReady && (!identifySpeakers || speakersReady) }
    var summaryProviderReady: Bool {
        switch summarySettings.backend {
        case .onDevice: OnDeviceSummaryGenerator.unavailableReason == nil
        case .chatGPT: !chatGPT.busy && summarySettings.chatGPTAccountID != nil && summarySettings.chatGPTModel?.isEmpty == false
        case .endpoint: (try? summarySettings.completionURL()) != nil
        }
    }


    override init() {
        do {
            let override = ProcessInfo.processInfo.environment["TRANSCRIBE_LIBRARY_PATH"].map { URL(fileURLWithPath: $0) }
            store = try TranscriptStore(root: override)
        }
        catch { fatalError("Cannot open Transcribe's local storage: \(error.localizedDescription)") }
        engine = LocalSpeechEngine(models: store.models)
        pianissimo = PianissimoEngine(models: store.models)
        super.init()
        if let saved = UserDefaults.standard.string(forKey: "transcriptionModel"),
           let choice = TranscriptionModel(rawValue: saved) { transcriptionModel = choice }
        if let data = UserDefaults.standard.data(forKey: "summarySettings"),
           let saved = try? JSONDecoder().decode(SummarySettings.self, from: data) { summarySettings = saved }
        do { projects = try store.loadAll() }
        catch { errorMessage = error.localizedDescription }
        selectedID = projects.first?.id
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        Task { await refreshModels() }
        loadPlayback()
    }

    func refreshModels() async {
        pianissimoReady = await pianissimo.isPrepared()
        do {
            let state = try await engine.installation()
            whisperReady = state.whisperFolder.map { FileManager.default.fileExists(atPath: $0) } ?? false
            speakersReady = state.speakerFolder.map { FileManager.default.fileExists(atPath: $0) } ?? false
        } catch {
            whisperReady = false
            speakersReady = false
            errorMessage = error.localizedDescription
        }
    }

    private func tick() {
        if let recorder, isRecording {
            recordingSeconds = recorder.currentTime
            recorder.updateMeters()
            recordingLevel = isPaused ? 0 : max(0, min(1, pow(10, Double(recorder.averagePower(forChannel: 0)) / 25)))
        }
        if let player {
            playhead = player.currentTime
            isPlaying = player.isPlaying
        }
    }

    func select(_ id: UUID?) {
        guard !locked else { return }
        selectedID = id
        loadPlayback()
    }

    private func put(_ transcript: Transcript) throws {
        // Persist first so a failed disk write cannot erase the last saved version.
        try store.save(transcript)
        if let index = projects.firstIndex(where: { $0.id == transcript.id }) { projects[index] = transcript }
        else { projects.insert(transcript, at: 0) }
        selectedID = transcript.id
    }

    func edit(_ change: (inout Transcript) -> Void) {
        guard !locked, var transcript = selected else { return }
        change(&transcript)
        if let index = projects.firstIndex(where: { $0.id == transcript.id }) { projects[index] = transcript }
        do { try store.save(transcript); saveFailed = false }
        catch { saveFailed = true; status = "Changes are in memory. Saving failed: \(error.localizedDescription)" }
    }

    func retrySave() {
        guard let transcript = selected else { return }
        do { try store.save(transcript); saveFailed = false; status = "Saved" }
        catch { errorMessage = error.localizedDescription }
    }

    func saveSpeakerNames(_ names: [String: String], for id: UUID) throws {
        guard !locked, !saveFailed, var transcript = selected, transcript.id == id else {
            throw TranscribeError.message("Names cannot be changed while this recording is unavailable or processing.")
        }
        guard transcript.speakerNames != names else { return }
        transcript.speakerNames = names
        try put(transcript)
    }

    var canManageRecording: Bool { !locked && !saveFailed && selected != nil }

    func renameRecording(_ id: UUID? = nil) {
        guard !locked, !saveFailed, let index = projects.firstIndex(where: { $0.id == (id ?? selectedID) }) else { return }
        let transcript = projects[index]
        let alert = NSAlert()
        alert.messageText = "Rename Recording"
        alert.informativeText = "Enter a name for this recording."
        let field = NSTextField(string: transcript.title)
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 26)
        field.font = .systemFont(ofSize: 14)
        field.setAccessibilityLabel("Recording name")
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn, !locked, !saveFailed else { return }
        let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { errorMessage = "Enter a recording name that is not blank."; return }
        var renamed = transcript
        renamed.title = title
        do {
            try store.save(renamed)
            if let current = projects.firstIndex(where: { $0.id == transcript.id }) { projects[current] = renamed }
        } catch { errorMessage = "Cannot rename this recording: \(error.localizedDescription)" }
    }

    func deleteRecording(_ id: UUID? = nil) {
        guard !locked, !saveFailed, let index = projects.firstIndex(where: { $0.id == (id ?? selectedID) }) else { return }
        let transcript = projects[index]
        let alert = NSAlert()
        alert.messageText = "Move “\(transcript.title)” to Trash?"
        alert.informativeText = "This moves the recording's saved audio, transcript and summary to the Mac’s Trash. You can recover the project folder from Trash. Imported source files stay where they are."
        alert.alertStyle = .warning
        let trashButton = alert.addButton(withTitle: "Move to Trash")
        trashButton.hasDestructiveAction = true
        trashButton.keyEquivalent = ""
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\r"
        guard alert.runModal() == .alertFirstButtonReturn, !locked, !saveFailed else { return }
        let deletingSelection = selectedID == transcript.id
        if deletingSelection { player?.stop(); player = nil; isPlaying = false }
        do {
            try store.trash(transcript.id)
            projects.removeAll { $0.id == transcript.id }
            if deletingSelection {
                selectedID = projects.isEmpty ? nil : projects[min(index, projects.count - 1)].id
                loadPlayback()
            }
        } catch {
            if deletingSelection { loadPlayback() }
            errorMessage = "Cannot move this recording to Trash: \(error.localizedDescription)"
        }
    }

    func openFile() {
        guard !locked else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.prompt = "Import Audio"
        if panel.runModal() == .OK, let url = panel.url { importAudio(url) }
    }

    func importAudio(_ url: URL) {
        guard !locked, !saveFailed else { return }
        player?.stop()
        run("Importing audio…") { [self] _ in
            let transcript = try await store.importAudio(url)
            try Task.checkCancellation()
            try put(transcript)
            loadPlayback()
        }
    }

    private func run(_ initial: String, operation: @escaping @MainActor (UUID) async throws -> Void) {
        guard !isBusy else { return }
        let id = UUID()
        operationID = id
        isBusy = true
        status = initial
        fraction = nil
        task = Task {
            defer {
                if operationID == id { isBusy = false; fraction = nil; transcriptionPreview = nil; operationID = nil; task = nil }
            }
            do {
                try await operation(id)
                if !Task.isCancelled { status = "Saved on this Mac" }
            } catch is CancellationError { status = "Cancelled. Saved audio and transcript retained." }
            catch {
                if Task.isCancelled { status = "Cancelled. Saved audio and transcript retained." }
                else { errorMessage = error.localizedDescription; status = "Processing stopped. Saved work retained." }
            }
        }
    }

    private func progress(for id: UUID) -> ProgressHandler {
        { [weak self] update in
            await self?.receive(update, for: id)
        }
    }

    private func receive(_ update: EngineProgress, for id: UUID) {
        guard operationID == id, task?.isCancelled == false else { return }
        status = update.message
        fraction = update.fraction.flatMap { $0.isFinite ? max(0, min(1, $0)) : nil }
        if transcriptionPreview != nil, let preview = update.transcription { transcriptionPreview = preview }
    }

    func cancel() {
        task?.cancel()
        fraction = nil
        status = "Cancelling… Saved work will be retained."
    }

    func prepareModels() {
        let choice = transcriptionModel
        let speakers = identifySpeakers
        run("Preparing local models…") { [self] id in
            do {
                switch choice {
                case .whisperTurbo: try await engine.prepare(speakers: speakers, progress: progress(for: id))
                case .pianissimo:
                    try await pianissimo.prepare(progress: progress(for: id))
                    if speakers { try await engine.prepareSpeakers(progress: progress(for: id)) }
                }
            }
            catch { await refreshModels(); throw error }
            await refreshModels()
        }
    }

    func transcribe() {
        guard !locked, !saveFailed, let transcript = selected else { return }
        guard transcriptionModel.supports(language: language == "auto" ? nil : language) else {
            errorMessage = "Pianissimo is Swedish-only. Select Whisper in Settings → Local Models for English or mixed recordings."
            return
        }
        guard modelsReady else { showModels = true; return }
        if !transcript.segments.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Replace this transcript?"
            alert.informativeText = "Transcribing again replaces the text and speaker labels, including your edits. The audio is kept."
            alert.addButton(withTitle: "Transcribe Again")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        player?.stop()
        let selectedLanguage = language == "auto" ? nil : language
        let transcriber: any TranscriptionEngine = transcriptionModel == .pianissimo ? pianissimo : engine
        let includeSpeakers = identifySpeakers
        let count = expectedSpeakers == 0 ? nil : expectedSpeakers
        showSummary = false
        transcriptionPreview = .init(duration: transcript.duration)
        run("Starting transcription…") { [self] id in
            let audio = try store.audioURL(transcript)
            let result = try await transcriber.transcribe(audio: audio, transcript: transcript,
                language: selectedLanguage, progress: progress(for: id))
            try Task.checkCancellation()
            try put(result)
            transcriptionPreview = nil
            if includeSpeakers, !result.segments.isEmpty {
                let attributed = try await engine.identifySpeakers(audio: audio, transcript: result,
                    count: count, progress: progress(for: id))
                try Task.checkCancellation()
                try put(attributed)
            }
        }
    }

    func addSpeakers() {
        guard !locked, !saveFailed, let transcript = selected, !transcript.segments.isEmpty else { return }
        guard speakersReady else { identifySpeakers = true; showModels = true; return }
        if transcript.speakersIdentified, !transcript.speakerNames.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Identify speakers again?"
            alert.informativeText = "Voice labels can change between runs, so speaker names will be cleared. Your edited text is kept."
            alert.addButton(withTitle: "Identify Again")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let count = expectedSpeakers == 0 ? nil : expectedSpeakers
        run("Starting speaker identification…") { [self] id in
            let result = try await engine.identifySpeakers(audio: store.audioURL(transcript), transcript: transcript,
                count: count, progress: progress(for: id))
            try Task.checkCancellation()
            try put(result)
        }
    }

    func summarise() {
        guard !locked, !saveFailed, let transcript = selected, !transcript.segments.isEmpty else { return }
        let settings = summarySettings
        let generator: any SummaryTextGenerator
        do {
            if settings.backend == .onDevice {
                if let reason = OnDeviceSummaryGenerator.unavailableReason { throw TranscribeError.message(reason) }
                generator = OnDeviceSummaryGenerator()
            } else if settings.backend == .chatGPT {
                guard !chatGPT.busy else { throw TranscribeError.message("Finish connecting or signing out of ChatGPT before summarising.") }
                guard let id = settings.chatGPTAccountID, let model = settings.chatGPTModel, !model.isEmpty else {
                    throw TranscribeError.message("Connect your ChatGPT account and choose a model in Settings first.")
                }
                generator = ChatGPTSummaryGenerator(client: chatGPT.client, accountID: id, model: model)
            } else {
                _ = try settings.completionURL()
                generator = EndpointSummaryGenerator(settings: settings, apiKey: try SummaryKeychain.read(settings))
            }
        } catch { errorMessage = error.localizedDescription; return }
        if transcript.summary != nil {
            let alert = NSAlert()
            alert.messageText = "Replace this summary?"
            alert.informativeText = "A successful new summary will replace this one, including any edits. The transcript is kept."
            alert.addButton(withTitle: "Regenerate")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        showSummary = true
        run("Starting summary…") { [self] id in
            let result = try await SummaryService.generate(transcript: transcript, settings: settings,
                using: generator, progress: progress(for: id))
            try Task.checkCancellation()
            var updated = transcript
            updated.summary = result
            try put(updated)
        }
    }

    func copySummary() {
        guard let text = selected?.summary?.text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func exportSummary(_ format: ExportFormat) {
        guard let selected, let summary = selected.summary else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: format.rawValue) ?? .plainText]
        panel.nameFieldStringValue = selected.title.replacingOccurrences(of: "/", with: "-") + " - Summary." + format.rawValue
        if panel.runModal() == .OK, let url = panel.url {
            do { try summary.exported(as: format).write(to: url, options: .atomic) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func startRecording() {
        guard !locked, !saveFailed else { return }
        Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard allowed else {
                errorMessage = "Microphone access is needed to record. Enable Transcribe in System Settings → Privacy & Security → Microphone."
                return
            }
            guard !locked else { return }
            do {
                player?.stop()
                let transcript = try store.createRecording()
                let recorder = try AVAudioRecorder(url: store.audioURL(transcript), settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                ])
                recorder.delegate = self
                recorder.isMeteringEnabled = true
                guard recorder.prepareToRecord(), recorder.record() else {
                    throw TranscribeError.message("The microphone recording could not be started.")
                }
                self.recorder = recorder
                try put(transcript)
                waveform = []
                playhead = 0
                playerDuration = 0
                recordingSeconds = 0
                isRecording = true
                isPaused = false
                status = "Recording from the default microphone"
            } catch { recorder?.stop(); recorder = nil; errorMessage = error.localizedDescription }
        }
    }

    func togglePause() {
        guard let recorder else { return }
        if isPaused {
            guard recorder.record() else { errorMessage = "Recording could not be resumed."; return }
        } else { recorder.pause() }
        isPaused.toggle()
    }

    func stopRecording(transcribeAfter: Bool = true) {
        guard let recorder, var transcript = selected else { return }
        transcript.duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        isRecording = false
        isPaused = false
        do {
            try put(transcript)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: store.audioURL(transcript).path)
            loadPlayback()
            if transcribeAfter { transcribe() }
        } catch { errorMessage = error.localizedDescription }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let message = error?.localizedDescription ?? "The microphone recording stopped unexpectedly."
        Task { @MainActor [weak self] in
            self?.stopRecording(transcribeAfter: false)
            self?.errorMessage = message
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, isRecording else { return }
            stopRecording(transcribeAfter: false)
            if !flag { errorMessage = "Recording was interrupted. The audio captured so far has been retained." }
        }
    }

    func loadPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
        playhead = 0
        playerDuration = 0
        waveform = []
        guard let transcript = selected else { return }
        do {
            let url = try store.audioURL(transcript)
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.prepareToPlay()
            player = audio
            playerDuration = audio.duration
            if transcript.duration == 0, audio.duration > 0 {
                var recovered = transcript
                recovered.duration = audio.duration
                try put(recovered)
            }
            let id = transcript.id
            Task {
                let values = await Task.detached(priority: .utility) { try? Self.peaks(url) }.value
                if selectedID == id { waveform = values ?? [] }
            }
        } catch { errorMessage = "Cannot play this recording: \(error.localizedDescription)" }
    }

    nonisolated private static func peaks(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192), file.length > 0 else { return [] }
        var bins = [Float](repeating: 0, count: 160)
        var offset: AVAudioFramePosition = 0
        while offset < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer)
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { break }
            for frame in stride(from: 0, to: Int(buffer.frameLength), by: 16) {
                let bin = min(159, Int(Double(offset + Int64(frame)) / Double(file.length) * 160))
                for channel in 0..<Int(format.channelCount) { bins[bin] = max(bins[bin], abs(channels[channel][frame])) }
            }
            offset += Int64(buffer.frameLength)
        }
        let maximum = bins.max() ?? 1
        return bins.map { maximum > 0 ? $0 / maximum : 0 }
    }

    func togglePlayback() {
        guard !isRecording, let player else { return }
        if player.isPlaying { player.pause() }
        else { if player.currentTime >= player.duration { player.currentTime = 0 }; player.play() }
        isPlaying = player.isPlaying
    }

    func seek(_ seconds: Double, play: Bool = false) {
        guard let player else { return }
        player.currentTime = max(0, min(seconds, player.duration))
        playhead = player.currentTime
        if play { player.play(); isPlaying = player.isPlaying }
    }

    func copyTranscript() {
        guard let selected, let data = try? selected.exported(as: .text), let text = String(data: data, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func export(_ format: ExportFormat) {
        guard let selected else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: format.rawValue) ?? .plainText]
        panel.nameFieldStringValue = selected.title.replacingOccurrences(of: "/", with: "-") + "." + format.rawValue
        if panel.runModal() == .OK, let url = panel.url {
            do { try selected.exported(as: format).write(to: url, options: .atomic) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func prepareToQuit() async -> Bool {
        chatGPT.cancel()
        stopRecording(transcribeAfter: false)
        task?.cancel()
        await task?.value
        if saveFailed { retrySave() }
        return !saveFailed
    }
}
